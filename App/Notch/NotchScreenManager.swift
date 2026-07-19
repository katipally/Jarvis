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
    private var core: JarvisCore?
    private var chat: ChatStore?
    private var voice: VoiceController?

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
    private static let systemDialogAgents: Set<String> = [
        "com.apple.UserNotificationCenter",   // TCC permission alerts
        "com.apple.SecurityAgent",            // keychain / authorization
        "com.apple.coreservices.uiagent",     // gatekeeper & consent prompts
        "com.apple.CoreLocationAgent",
        "com.apple.accessibility.universalAccessAuthWarn",
    ]

    func start(core: JarvisCore, chat: ChatStore, voice: VoiceController) {
        self.core = core
        self.chat = chat
        self.voice = voice
        rebuild()

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
            MainActor.assumeIsolated { self?.pointerMoved() }
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    func stop() {
        rebuildTask?.cancel()
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
        let root = NotchView(vm: vm, core: core, chat: chat, voice: voice)
        window.contentView = NotchHostingView(rootView: root)
        vm.attach(window: window)
        window.orderFrontRegardless()
        return Panel(window: window, vm: vm)
    }

    private func pointerMoved() {
        let pointer = NSEvent.mouseLocation
        for (_, panel) in panels where panel.vm.state == .open {
            // Close on the real visible region, not the (larger) fixed window.
            let zone = panel.vm.visibleRect(open: true).insetBy(dx: -36, dy: -36)
            if !zone.contains(pointer), panel.vm.canAutoClose {
                withAnimation(NotchAnimation.close) {
                    panel.vm.close()
                }
            }
        }
    }
}
