import Foundation

/// A streaming speech-to-text event. `partial` is a live best-guess for the
/// current utterance; `final` is the accumulated finalized transcript; `level`
/// is a 0…1 audio level for the waveform.
public enum TranscriptEvent: Sendable {
    case partial(String)
    case final(String)
    case level(Float)
}

public enum SpeechError: Error, LocalizedError {
    case micNotAuthorized
    case unsupportedLocale
    case engineFailed(String)

    public var errorDescription: String? {
        switch self {
        case .micNotAuthorized: "Microphone access is required for voice input."
        case .unsupportedLocale: "This language isn't supported for on-device transcription."
        case .engineFailed(let m): "Voice engine error: \(m)"
        }
    }
}

/// The seam that lets the STT backend be swapped (SpeechAnalyzer today; a
/// SFSpeechRecognizer fallback could implement the same protocol).
public protocol TranscriberEngine: Sendable {
    /// Begin capturing + transcribing. The returned stream ends when `stop()`
    /// is called or an error occurs.
    func start(locale: Locale) async throws -> AsyncStream<TranscriptEvent>
    /// Stop capture and finalize; returns the full final transcript.
    @discardableResult
    func stop() async -> String
}
