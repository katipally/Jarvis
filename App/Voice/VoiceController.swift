import AppKit
import JSpeech
import Observation

/// Owns a push-to-talk voice session: starts the transcriber, streams live words
/// + audio level for the notch, and on release sends the transcript to the chat.
@MainActor
@Observable
final class VoiceController {
    enum Phase: Equatable { case idle, listening, processing, review, ready }

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
    private var reviewTimeoutTask: Task<Void, Never>?

    init(chat: ChatStore, makeEngine: @escaping @Sendable () -> any TranscriberEngine = { SpeechAnalyzerEngine() }) {
        self.chat = chat
        self.makeEngine = makeEngine
    }

    var isActive: Bool { phase == .listening || phase == .processing || phase == .review }
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
                // Review before send: the transcript is shown in full with
                // explicit send/cancel instead of firing on release.
                self.finalized = text
                self.partial = ""
                self.phase = .review
                // A forgotten review must not linger armed forever — after 30s
                // the transcript lands in the composer as a draft instead.
                self.reviewTimeoutTask?.cancel()
                self.reviewTimeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(30))
                    guard !Task.isCancelled else { return }
                    self?.abandonReview()
                }
            }
        }
    }

    /// Confirms the reviewed transcript and sends it.
    func confirmSend() {
        guard phase == .review else { return }
        reviewTimeoutTask?.cancel()
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { phase = .idle; return }
        // If a run is already streaming, send() would silently no-op — park the
        // transcript in the composer instead of pretending it was sent.
        guard let chat, chat.phase == .idle else { abandonReview(); return }
        phase = .processing
        sendAndAwaitAnswer(text)
    }

    /// Exits review without sending, salvaging the transcript into the composer
    /// (unless a draft is already there). Used when the review UI goes away
    /// without a decision: timeout, or the panel opening over it.
    func abandonReview() {
        guard phase == .review else { return }
        reviewTimeoutTask?.cancel()
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if let chat, !text.isEmpty, chat.input.trimmingCharacters(in: .whitespaces).isEmpty {
            chat.input = text
        }
        finalized = ""
        partial = ""
        phase = .idle
    }

    func cancel() {
        guard phase == .listening || phase == .processing || phase == .review else { return }
        reviewTimeoutTask?.cancel()
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
        case .review: confirmSend()
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
        let draft = chat.input // never clobber a half-typed message
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
        if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chat.input = draft
        }
    }
}
