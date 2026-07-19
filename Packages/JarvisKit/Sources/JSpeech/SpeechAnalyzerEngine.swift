@preconcurrency import AVFoundation
import Foundation
import Speech

/// On-device streaming transcription via macOS 26 SpeechAnalyzer + SpeechTranscriber.
/// Audio callbacks run on a realtime thread; state is confined accordingly.
public final class SpeechAnalyzerEngine: TranscriberEngine, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var resultsTask: Task<Void, Never>?
    private var eventContinuation: AsyncStream<TranscriptEvent>.Continuation?
    private var finalizedText = ""

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
        self.transcriber = transcriber
        try await ensureModel(for: transcriber, locale: locale)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        self.analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputBuilder = inputBuilder

        let (events, eventContinuation) = AsyncStream<TranscriptEvent>.makeStream()
        self.eventContinuation = eventContinuation
        finalizedText = ""

        resultsTask = Task { [weak self] in
            guard let transcriber = self?.transcriber else { return }
            do {
                for try await result in transcriber.results {
                    guard let self else { return }
                    let text = String(result.text.characters)
                    if result.isFinal {
                        self.finalizedText += text
                        eventContinuation.yield(.final(self.finalizedText))
                    } else {
                        eventContinuation.yield(.partial(text))
                    }
                }
            } catch {
                // Stream ended or was cancelled.
            }
        }

        try await analyzer.start(inputSequence: inputSequence)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        if let analyzerFormat, inputFormat != analyzerFormat {
            converter = AVAudioConverter(from: inputFormat, to: analyzerFormat)
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            eventContinuation.yield(.level(Self.rms(buffer)))
            if let converted = self.convert(buffer) {
                self.inputBuilder?.yield(AnalyzerInput(buffer: converted))
            } else {
                self.inputBuilder?.yield(AnalyzerInput(buffer: buffer))
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw SpeechError.engineFailed(error.localizedDescription)
        }

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
        return text
    }

    // MARK: - Audio

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter, let analyzerFormat else { return nil }
        let ratio = analyzerFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else { return nil }
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
