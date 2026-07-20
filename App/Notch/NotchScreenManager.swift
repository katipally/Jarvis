import AppKit
import SwiftUI

/// Owns one notch panel per display. The notch is visible on every screen but
/// only the panel under the mouse ever expands.
@MainActor
final class NotchScreenManager {
    private struct Panel {
        let window: NotchWindow
        let vm: NotchViewModel
    }

    private var panels: [CGDirectDisplayID: Panel] = [:]
    private var screenObserver: NSObjectProtocol?
    private var appActivationObserver: NSObjectProtocol?
    private var rebuildTask: Task<Void, Never>?
    private var mouseMonitors: [Any] = []
    /// Per-panel timestamp of when the pointer first left its close zone; reset
    /// to nil whenever the pointer is back inside (or while aiming toward it).
    /// Drives the grace dwell.
    private var outsideSince: [CGDirectDisplayID: Date] = [:]
    /// Previous pointer sample per panel, so we can tell whether the pointer is
    /// moving TOWARD the panel (intent) versus drifting away.
    private var lastPointer: [CGDirectDisplayID: CGPoint] = [:]
    /// Fires a delayed pointerMoved so a stationary-while-outside pointer still
    /// triggers the close. One pending task at a time.
    private var outsideRecheckTask: Task<Void, Never>?
    private var core: JarvisCore?
    private var chat: ChatStore?
    private var voice: VoiceController?
    private var meetings: MeetingService?

    /// Lock-free-enough throttle usable from the monitor callback thread.
    private final class PointerThrottle: @unchecked Sendable {
        private let lock = NSLock()
        private var last = Date.distantPast
        func shouldFire() -> Bool {
            lock.withLock {
                guard Date.now.timeIntervalSince(last) > 0.08 else { return false }
                last = .now
                return true
            }
        }
    }

    /// System agents that present permission/auth dialogs. While one of these is
    /// frontmost, panels drop below dialog level so the prompt is never hidden
    /// behind the notch.
    private nonisolated static let systemDialogAgents: Set<String> = [
        "com.apple.UserNotificationCenter",   // TCC permission alerts
        "com.apple.SecurityAgent",            // keychain / authorization
        "com.apple.coreservices.uiagent",     // gatekeeper & consent prompts
        "com.apple.CoreLocationAgent",
        "com.apple.accessibility.universalAccessAuthWarn",
    ]

    func start(core: JarvisCore, chat: ChatStore, voice: VoiceController, meetings: MeetingService? = nil) {
        self.core = core
        self.chat = chat
        self.voice = voice
        self.meetings = meetings
        rebuild()

        // A clicked proactive notification opens the primary panel.
        NotificationCenter.default.addObserver(
            forName: NotificationService.openNotch, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                (self.panels[CGMainDisplayID()] ?? self.panels.first?.value)?.vm.open()
            }
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleRebuild() }
        }

        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .bundleIdentifier
            let yields = bundleID.map(Self.systemDialogAgents.contains) ?? false
            Task { @MainActor in
                guard let self else { return }
                for (_, panel) in self.panels {
                    panel.window.setYieldsToSystemDialog(yields)
                }
            }
        }

        // Pointer monitors are installed lazily (see updateMouseMonitors): while
        // the notch is closed there is nothing to auto-close, so nothing tracks
        // the mouse and idle CPU stays at ~0%.
    }

    /// The pointer monitors drive ONE thing — auto-close — which only matters
    /// while a panel is open. Hover-to-open is handled by SwiftUI, so closed =
    /// no mouse tracking = ~0% idle CPU. Installed on the first open, removed
    /// when the last panel closes (via each view-model's onStateChange).
    private func installMouseMonitors() {
        guard mouseMonitors.isEmpty else { return }
        // SwiftUI onHover can miss exit events during animated resizes, so the
        // real pointer position is the authoritative close signal. Throttle
        // before the actor hop — this fires for every pointer move on screen.
        let throttle = PointerThrottle()
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            guard throttle.shouldFire() else { return }
            Task { @MainActor in self?.pointerMoved() }
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            // Hop off the handler stack: closing the last panel removes these
            // monitors synchronously, and removing a monitor from inside its own
            // handler is unsafe.
            Task { @MainActor in self?.pointerMoved() }
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    private func removeMouseMonitors() {
        for monitor in mouseMonitors { NSEvent.removeMonitor(monitor) }
        mouseMonitors.removeAll()
        outsideRecheckTask?.cancel()
        outsideSince.removeAll()
        lastPointer.removeAll()
    }

    /// Keep the monitors installed exactly while at least one panel is open.
    private func updateMouseMonitors() {
        if panels.values.contains(where: { $0.vm.state == .open }) {
            installMouseMonitors()
        } else {
            removeMouseMonitors()
        }
    }

    func stop() {
        rebuildTask?.cancel()
        outsideRecheckTask?.cancel()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appActivationObserver)
        }
        for monitor in mouseMonitors {
            NSEvent.removeMonitor(monitor)
        }
        mouseMonitors.removeAll()
        for (_, panel) in panels {
            panel.vm.cancelHoverTasks()
            panel.window.orderOut(nil)
        }
    }

    /// Display hot-plug/sleep fires bursts of change notifications; settle first.
    private func scheduleRebuild() {
        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else { return }
            self?.rebuild()
        }
    }

    private func rebuild() {
        var seen: Set<CGDirectDisplayID> = []

        for screen in NSScreen.screens {
            let id = screen.jarvisDisplayID
            seen.insert(id)
            if let panel = panels[id] {
                panel.vm.refresh(for: screen)
            } else {
                panels[id] = makePanel(for: screen)
            }
        }

        for (id, panel) in panels where !seen.contains(id) {
            panel.vm.cancelHoverTasks()
            panel.window.orderOut(nil)
            panels.removeValue(forKey: id)
            outsideSince.removeValue(forKey: id)
        }
    }

    private func makePanel(for screen: NSScreen) -> Panel {
        let vm = NotchViewModel(screen: screen)
        let window = NotchWindow(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        let root = NotchView(vm: vm, core: core, chat: chat, voice: voice, meetings: meetings)
        window.contentView = NotchHostingView(rootView: root)
        vm.attach(window: window)
        vm.onStateChange = { [weak self] in self?.updateMouseMonitors() }
        window.orderFrontRegardless()
        return Panel(window: window, vm: vm)
    }

    /// The single auto-close authority. The close zone is the SOLID region from
    /// the notch body's top down to the floating tray's bottom (body ∪ tray,
    /// generously inset) — so moving onto the composer / Stop pill never reads as
    /// "left the panel" (the old body-only zone is what auto-closed voice input).
    /// While the pointer is aiming toward that zone (intent), the grace dwell is
    /// held; only a clear move away arms the ~0.45s close.
    private func pointerMoved() {
        let pointer = NSEvent.mouseLocation
        let now = Date.now
        var awaitingClose = false

        for (id, panel) in panels where panel.vm.state == .open {
            let zone = closeZone(panel.vm)
            if zone.contains(pointer) {
                outsideSince[id] = nil
                lastPointer[id] = pointer
                continue
            }

            let prev = lastPointer[id] ?? pointer
            lastPointer[id] = pointer

            // Intent: still heading toward the panel → hold the close, but keep
            // re-checking since the pointer may stop.
            if isAiming(toward: zone, from: prev, to: pointer) {
                outsideSince[id] = nil
                awaitingClose = true
                continue
            }

            let since = outsideSince[id] ?? now
            outsideSince[id] = since

            if now.timeIntervalSince(since) >= 0.45, canAutoClose(panel) {
                outsideSince[id] = nil
                withAnimation(NotchAnimation.close) { panel.vm.close() }
            } else {
                // Dwell not yet elapsed, or a guard is holding it open; the
                // pointer may now be stationary, so re-check on a timer.
                awaitingClose = true
            }
        }

        if awaitingClose {
            scheduleOutsideRecheck()
        } else {
            outsideRecheckTask?.cancel()
        }
    }

    /// The solid body∪tray region, generously inset so the body↔tray gap and
    /// small overshoots stay "inside".
    private func closeZone(_ vm: NotchViewModel) -> CGRect {
        vm.visibleRect(open: true).union(vm.trayRect(open: true)).insetBy(dx: -48, dy: -44)
    }

    /// Apple's "menu aim" intent, in velocity-cone form: the pointer counts as
    /// aiming when it moved closer to the zone since the last sample AND its
    /// movement points into the zone (within ~60° of straight-at-it). A
    /// stationary or receding pointer is not aiming, so the dwell can run.
    private func isAiming(toward zone: CGRect, from prev: CGPoint, to cur: CGPoint) -> Bool {
        func distance(_ p: CGPoint) -> CGFloat {
            let dx = max(zone.minX - p.x, 0, p.x - zone.maxX)
            let dy = max(zone.minY - p.y, 0, p.y - zone.maxY)
            return (dx * dx + dy * dy).squareRoot()
        }
        guard distance(cur) < distance(prev) - 0.5 else { return false }
        let move = CGVector(dx: cur.x - prev.x, dy: cur.y - prev.y)
        let toZone = CGVector(dx: zone.midX - prev.x, dy: zone.midY - prev.y)
        let moveMag = (move.dx * move.dx + move.dy * move.dy).squareRoot()
        let zoneMag = (toZone.dx * toZone.dx + toZone.dy * toZone.dy).squareRoot()
        guard moveMag > 0.5, zoneMag > 0.5 else { return false }
        let cosine = (move.dx * toZone.dx + move.dy * toZone.dy) / (moveMag * zoneMag)
        return cosine > 0.5
    }

    /// The pointer can stop moving while outside a panel; without a timed
    /// re-check the 0.75s dwell (or a lifted guard) would never be observed.
    private func scheduleOutsideRecheck() {
        outsideRecheckTask?.cancel()
        outsideRecheckTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.25))
            guard !Task.isCancelled else { return }
            self?.pointerMoved()
        }
    }

    /// Pointer-tracking close is allowed only when the view-model's own grace
    /// (state / holdOpen / 0.6s-since-open) passes AND nothing here demands the
    /// panel stay up: an in-flight response, an active voice session, or a held
    /// mouse button (drag / text selection in progress).
    private func canAutoClose(_ panel: Panel) -> Bool {
        guard panel.vm.canAutoClose else { return false }
        if chat?.phase == .responding { return false }
        if chat?.isWorkingCompact == true { return false }
        if voice?.isActive == true { return false }
        if NSEvent.pressedMouseButtons != 0 { return false }
        return true
    }
}
