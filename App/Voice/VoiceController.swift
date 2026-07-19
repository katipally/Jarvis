import AppKit
import JSpeech
import Observation

/// Owns a push-to-talk voice session: starts the transcriber, streams live words
/// + audio level for the notch, and on release sends the transcript to the chat.
@MainActor
@Observable
final class VoiceController {
    enum Phase: Equatable { case idle, listening, processing, ready }

    var phase: Phase = .idle
    var level: Float = 0
    /// The display the voice UI should appear on — the screen the user is on.
    var activeDisplayID: CGDirectDisplayID = CGMainDisplayID()

    /// Finalized text plus the current volatile guess.
    var transcript: String { finalized + partial }

    private var finalized = ""
    private var partial = ""

    private weak var chat: ChatStore?
    private let makeEngine: @Sendable () -> any TranscriberEngine
    private var engine: (any TranscriberEngine)?
    private var eventsTask: Task<Void, Never>?
    private var readyResetTask: Task<Void, Never>?

    init(chat: ChatStore, makeEngine: @escaping @Sendable () -> any TranscriberEngine = { SpeechAnalyzerEngine() }) {
        self.chat = chat
        self.makeEngine = makeEngine
    }

    var isActive: Bool { phase == .listening || phase == .processing }
    var showsGlow: Bool { phase != .idle }

    func beginListening() {
        guard phase == .idle, chat?.phase != .responding else { return }
        activeDisplayID = Self.screenUnderMouse()
        readyResetTask?.cancel()
        finalized = ""
        partial = ""
        level = 0
        phase = .listening

        let engine = makeEngine()
        self.engine = engine
        eventsTask = Task { [weak self] in
            do {
                let stream = try await engine.start(locale: .current)
                for await event in stream {
                    guard let self else { break }
                    switch event {
                    case .partial(let text): self.partial = text
                    case .final(let text): self.finalized = text; self.partial = ""
                    case .level(let value): self.level = value
                    }
                }
            } catch {
                guard let self else { return }
                self.phase = .idle
                self.chat?.errorText = (error as? SpeechError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func endListening() {
        guard phase == .listening else { return }
        phase = .processing
        level = 0
        let engine = self.engine
        eventsTask?.cancel()
        Task { [weak self] in
            let finalText = await engine?.stop() ?? ""
            guard let self else { return }
            self.engine = nil
            let text = (finalText.isEmpty ? self.transcript : finalText)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                self.phase = .idle
            } else {
                self.sendAndAwaitAnswer(text)
            }
        }
    }

    func cancel() {
        guard phase == .listening || phase == .processing else { return }
        let engine = self.engine
        eventsTask?.cancel()
        Task { _ = await engine?.stop() }
        self.engine = nil
        finalized = ""
        partial = ""
        level = 0
        phase = .idle
    }

    func toggle() {
        switch phase {
        case .idle: beginListening()
        case .listening: endListening()
        default: break
        }
    }

    private static func screenUnderMouse() -> CGDirectDisplayID {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        return screen?.jarvisDisplayID ?? CGMainDisplayID()
    }

    private func sendAndAwaitAnswer(_ text: String) {
        guard let chat else { phase = .idle; return }
        chat.input = text
        chat.onRunComplete = { [weak self] in
            guard let self, self.phase == .processing else { return }
            self.phase = .ready
            self.readyResetTask?.cancel()
            self.readyResetTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                if self?.phase == .ready { self?.phase = .idle }
            }
            chat.onRunComplete = nil
        }
        chat.send()
    }
}
