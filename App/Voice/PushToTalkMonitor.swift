import AppKit

/// Hold-⌥ push-to-talk. After a short hold of Option *alone*, listening starts;
/// releasing sends; Esc cancels. Any other key/modifier aborts the trigger.
///
/// The global monitor requires Accessibility/Input-Monitoring permission to fire
/// while another app is focused; without it, hold-to-talk works only when Jarvis
/// is frontmost. The composer mic button is the always-available fallback.
@MainActor
final class PushToTalkMonitor {
    private let voice: VoiceController
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var holdTask: Task<Void, Never>?
    private var isHolding = false

    private let holdThreshold: Duration = .milliseconds(350)
    private static let escKeyCode: UInt16 = 53

    init(voice: VoiceController) { self.voice = voice }

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
    }

    func stop() {
        [globalMonitor, localMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        globalMonitor = nil
        localMonitor = nil
        holdTask?.cancel()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if mods == .option {
                beginHold()
            } else if mods.contains(.option) {
                cancelHold() // Option plus another modifier — not a clean hold.
            } else {
                endHold()
            }
        case .keyDown:
            if voice.phase == .listening, event.keyCode == Self.escKeyCode {
                voice.cancel()
                isHolding = false
            } else if holdTask != nil {
                cancelHold() // A different key during the hold aborts it.
            }
        default:
            break
        }
    }

    private func beginHold() {
        guard !isHolding, voice.phase == .idle else { return }
        isHolding = true
        holdTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.holdThreshold)
            guard !Task.isCancelled, self.isHolding else { return }
            self.voice.beginListening()
        }
    }

    private func endHold() {
        holdTask?.cancel()
        holdTask = nil
        guard isHolding else { return }
        isHolding = false
        if voice.phase == .listening { voice.endListening() }
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
        guard isHolding else { return }
        isHolding = false
        if voice.phase == .listening { voice.cancel() }
    }
}
