@preconcurrency import AVFoundation
import Foundation
import Speech

/// On-device streaming transcription via macOS 26 SpeechAnalyzer + SpeechTranscriber.
/// Audio callbacks run on a realtime thread; the tap closure captures everything it
/// needs as locals so it never races `stop()`, and cross-thread text goes through a lock.
public final class SpeechAnalyzerEngine: TranscriberEngine, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var eventContinuation: AsyncStream<TranscriptEvent>.Continuation?

    private let textLock = NSLock()
    private var _finalizedText = ""
    private var finalizedText: String {
        get { textLock.withLock { _finalizedText } }
        set { textLock.withLock { _finalizedText = newValue } }
    }
    private func appendFinalized(_ text: String) -> String {
        textLock.withLock {
            _finalizedText += text
            return _finalizedText
        }
    }

    public init() {}

    public func start(locale: Locale = .current) async throws -> AsyncStream<TranscriptEvent> {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw SpeechError.micNotAuthorized
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        try await ensureModel(for: transcriber, locale: locale)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        let (events, eventContinuation) = AsyncStream<TranscriptEvent>.makeStream()
        finalizedText = ""

        let resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self else { return }
                    let text = String(result.text.characters)
                    if result.isFinal {
                        eventContinuation.yield(.final(self.appendFinalized(text)))
                    } else {
                        eventContinuation.yield(.partial(text))
                    }
                }
            } catch {
                // Stream ended or was cancelled.
            }
        }

        // From here on, any failure must tear down what was started so a retry
        // begins clean (analyzer, results task, tap, streams).
        func teardown() async {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            inputBuilder.finish()
            resultsTask.cancel()
            eventContinuation.finish()
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }

        do {
            try await analyzer.start(inputSequence: inputSequence)

            let input = engine.inputNode
            let inputFormat = input.outputFormat(forBus: 0)
            var converter: AVAudioConverter?
            if let analyzerFormat, inputFormat != analyzerFormat {
                converter = AVAudioConverter(from: inputFormat, to: analyzerFormat)
            }

            // The tap runs on a realtime thread: capture locals only, never self.
            let tapConverter = converter
            let tapFormat = analyzerFormat
            input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
                eventContinuation.yield(.level(Self.rms(buffer)))
                if let tapConverter, let tapFormat,
                   let converted = Self.convert(buffer, using: tapConverter, to: tapFormat) {
                    inputBuilder.yield(AnalyzerInput(buffer: converted))
                } else {
                    inputBuilder.yield(AnalyzerInput(buffer: buffer))
                }
            }

            engine.prepare()
            try engine.start()
        } catch {
            await teardown()
            throw SpeechError.engineFailed(error.localizedDescription)
        }

        self.transcriber = transcriber
        self.analyzer = analyzer
        self.inputBuilder = inputBuilder
        self.resultsTask = resultsTask
        self.eventContinuation = eventContinuation
        return events
    }

    @discardableResult
    public func stop() async -> String {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        inputBuilder?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        resultsTask?.cancel()
        eventContinuation?.finish()
        let text = finalizedText
        transcriber = nil
        analyzer = nil
        inputBuilder = nil
        resultsTask = nil
        eventContinuation = nil
        return text
    }

    // MARK: - Audio

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

    /// One-shot "already consumed" flag for the converter input block.
    private final class ConsumeFlag: @unchecked Sendable {
        var consumed = false
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count {
            let sample = channel[i]
            sum += sample * sample
        }
        let rms = (sum / Float(count)).squareRoot()
        // Normalize to a lively 0…1 range for the waveform.
        return min(1, rms * 12)
    }

    private func ensureModel(for transcriber: SpeechTranscriber, locale: Locale) async throws {
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
