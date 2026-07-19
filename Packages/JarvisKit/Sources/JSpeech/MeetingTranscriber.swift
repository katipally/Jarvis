@preconcurrency import AVFoundation
import Foundation
import OSLog
import Speech

/// Where a meeting utterance came from. Attribution is intentionally coarse:
/// `mic` is the local user ("You"), `system` is everyone else ("Them"). No
/// diarization within a channel.
public enum MeetingAudioSource: String, Sendable {
    case mic
    case system
}

/// One finalized, attributed line of meeting transcript.
public struct MeetingUtterance: Sendable {
    public let source: MeetingAudioSource
    public let text: String
    public let ts: Date

    public init(source: MeetingAudioSource, text: String, ts: Date = .now) {
        self.source = source
        self.text = text
        self.ts = ts
    }
}

/// Runs two concurrent on-device SpeechAnalyzer sessions — one on the microphone,
/// one fed by `SystemAudioTap` — and merges their finalized utterances into a
/// single attributed stream.
///
/// FALLBACK: if the system-audio tap or its analyzer can't start (permission,
/// contention between two analyzers), the transcriber silently degrades to
/// MIC-ONLY. `systemAudioActive` reports which mode is live. A meeting never
/// fails to start just because "them" can't be captured.
public final class MeetingTranscriber: @unchecked Sendable {
    /// True when the system-audio ("them") channel is live; false in mic-only fallback.
    public private(set) var systemAudioActive = false

    private let log = Logger(subsystem: "com.jarvis.speech", category: "MeetingTranscriber")
    private let micEngine = AVAudioEngine()

    private var micSession: TranscriptionSession?
    private var systemSession: TranscriptionSession?
    private var systemTap: SystemAudioTap?
    private var systemPump: Task<Void, Never>?
    private var continuation: AsyncStream<MeetingUtterance>.Continuation?

    public init() {}

    /// Begin transcription. Throws only if the microphone is unauthorized (the
    /// system channel degrades gracefully instead of throwing).
    public func start(locale: Locale = .current) async throws -> AsyncStream<MeetingUtterance> {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw SpeechError.micNotAuthorized
        }

        let (events, continuation) = AsyncStream<MeetingUtterance>.makeStream()
        self.continuation = continuation

        // MIC channel — always on.
        let mic = TranscriptionSession(source: .mic) { text in
            continuation.yield(MeetingUtterance(source: .mic, text: text))
        }
        try await mic.start(locale: locale)
        startMicTap(into: mic)
        self.micSession = mic

        // SYSTEM channel — best-effort; degrade to mic-only on any failure.
        do {
            let system = TranscriptionSession(source: .system) { text in
                continuation.yield(MeetingUtterance(source: .system, text: text))
            }
            try await system.start(locale: locale)
            // Publish the started session before the next throwing call so the
            // catch below can stop it (a thrown tap.start() would otherwise leak
            // this live analyzer session).
            self.systemSession = system

            let tap = SystemAudioTap(sampleRate: 48_000)
            let buffers = try await tap.start()

            self.systemTap = tap
            self.systemAudioActive = true
            self.systemPump = Task { [weak self] in
                for await buffer in buffers {
                    self?.systemSession?.feed(buffer)
                }
            }
        } catch {
            log.error("system audio unavailable, continuing mic-only: \(error.localizedDescription, privacy: .public)")
            await systemSession?.stop()
            systemSession = nil
            systemTap = nil
            systemAudioActive = false
        }

        return events
    }

    public func stop() async {
        micEngine.inputNode.removeTap(onBus: 0)
        micEngine.stop()
        systemPump?.cancel()
        systemPump = nil
        await systemTap?.stop()
        systemTap = nil
        await micSession?.stop()
        micSession = nil
        await systemSession?.stop()
        systemSession = nil
        continuation?.finish()
        continuation = nil
        systemAudioActive = false
    }

    /// Installs a realtime tap on the mic and pipes buffers into the mic session.
    /// The tap runs on a realtime thread and captures only the (Sendable) session.
    private func startMicTap(into session: TranscriptionSession) {
        let input = micEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { @Sendable buffer, _ in
            session.feed(buffer)
        }
        micEngine.prepare()
        do {
            try micEngine.start()
        } catch {
            log.error("mic engine failed to start: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// One on-device SpeechAnalyzer session. Buffers are fed via `feed` (from a mic
/// tap or the system tap), converted to the analyzer's format on first use, and
/// each *finalized* utterance is delivered through `onFinal` — a per-utterance
/// delta (not an accumulating transcript), which is what meeting segments want.
///
/// `feed` is single-producer per session (mic tap OR system pump, never both),
/// so the lazily-built converter needs no locking.
private final class TranscriptionSession: @unchecked Sendable {
    let source: MeetingAudioSource
    private let onFinal: @Sendable (String) -> Void

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?

    init(source: MeetingAudioSource, onFinal: @escaping @Sendable (String) -> Void) {
        self.source = source
        self.onFinal = onFinal
    }

    func start(locale: Locale) async throws {
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
        try await Self.ensureModel(for: transcriber, locale: locale)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()

        let onFinal = self.onFinal
        let resultsTask = Task {
            do {
                for try await result in transcriber.results where result.isFinal {
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { onFinal(text) }
                }
            } catch {
                // Stream ended or was cancelled.
            }
        }

        try await analyzer.start(inputSequence: inputSequence)

        self.transcriber = transcriber
        self.analyzer = analyzer
        self.analyzerFormat = analyzerFormat
        self.inputBuilder = inputBuilder
        self.resultsTask = resultsTask
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let inputBuilder else { return }
        guard let analyzerFormat, analyzerFormat != buffer.format else {
            inputBuilder.yield(AnalyzerInput(buffer: buffer))
            return
        }
        if converter == nil {
            converter = AVAudioConverter(from: buffer.format, to: analyzerFormat)
        }
        guard let converter,
              let converted = Self.convert(buffer, using: converter, to: analyzerFormat) else { return }
        inputBuilder.yield(AnalyzerInput(buffer: converted))
    }

    func stop() async {
        inputBuilder?.finish()
        inputBuilder = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
        transcriber = nil
        converter = nil
    }

    // MARK: - Audio (mirrors SpeechAnalyzerEngine's convert/ensureModel)

    private static func convert(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var error: NSError?
        let flag = ConsumeFlag()
        converter.convert(to: output, error: &error) { _, status in
            if flag.consumed {
                status.pointee = .noDataNow
                return nil
            }
            flag.consumed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? output : nil
    }

    private final class ConsumeFlag: @unchecked Sendable {
        var consumed = false
    }

    private static func ensureModel(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        let target = locale.identifier(.bcp47)
        let supported = await SpeechTranscriber.supportedLocales
        guard supported.contains(where: { $0.identifier(.bcp47) == target }) else {
            throw SpeechError.unsupportedLocale
        }
        let installed = await SpeechTranscriber.installedLocales
        if installed.contains(where: { $0.identifier(.bcp47) == target }) { return }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }
}
