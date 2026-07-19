@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import OSLog
import ScreenCaptureKit

public enum SystemAudioTapError: Error, LocalizedError {
    case noDisplay
    case streamSetupFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noDisplay: "No display is available to capture system audio from."
        case .streamSetupFailed(let m): "System-audio capture couldn't start: \(m)"
        }
    }
}

/// ScreenCaptureKit audio-only tap. Captures everything the machine plays back
/// (the "them" side of a call) as `AVAudioPCMBuffer`s over an `AsyncStream`, with
/// our own process's audio excluded. This is the riskiest slice of meeting mode,
/// so it is deliberately self-contained and guards every failure — if SCK can't
/// start, `start()` throws and the caller degrades to mic-only.
///
/// SCK callbacks arrive on two different queues — `didOutputSampleBuffer` on the
/// private `sampleQueue`, `didStopWithError` on the delegate queue — and `stop()`
/// runs on yet another. The `stream`/`continuation` properties are therefore
/// mutated concurrently, so every read/write of them is serialized behind `lock`
/// (the thread-safe continuation methods are called on a local copy taken under
/// the lock, never while holding it). Screen Recording permission (which also
/// gates system audio) is prompted by the OS on first `startCapture()`.
public final class SystemAudioTap: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let log = Logger(subsystem: "com.jarvis.speech", category: "SystemAudioTap")
    private let sampleQueue = DispatchQueue(label: "com.jarvis.systemaudio.samples")
    private let sampleRate: Int

    /// Guards `stream` and `continuation`, which are touched from the sample queue,
    /// the delegate queue, and `stop()` concurrently.
    private let lock = NSLock()
    private var stream: SCStream?
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    /// - Parameter sampleRate: capture rate in Hz. 48 kHz is SCK's native rate;
    ///   the transcriber resamples to whatever SpeechAnalyzer wants.
    public init(sampleRate: Int = 48_000) {
        self.sampleRate = sampleRate
        super.init()
    }

    /// Begin capture. The returned stream ends on `stop()` or if the OS tears the
    /// stream down (permission revoked, display change).
    public func start() async throws -> AsyncStream<AVAudioPCMBuffer> {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            throw SystemAudioTapError.streamSetupFailed(error.localizedDescription)
        }
        guard let display = content.displays.first else { throw SystemAudioTapError.noDisplay }

        // Whole-display filter so audio from every app is captured; our own audio
        // is dropped via `excludesCurrentProcessAudio` below.
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = sampleRate
        config.channelCount = 1 // mono is plenty for transcription and avoids a downmix step
        // Audio-only: we never add a screen output, but SCK still needs a valid
        // video config. Keep it minimal so the unused screen path costs nothing.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.queueDepth = 6

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        } catch {
            throw SystemAudioTapError.streamSetupFailed(error.localizedDescription)
        }

        let (buffers, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        // Set the continuation BEFORE startCapture — delivery only begins after it.
        // Scoped withLock is async-safe (bare lock()/unlock() are not).
        lock.withLock {
            self.continuation = continuation
            self.stream = stream
        }

        do {
            try await stream.startCapture()
        } catch {
            continuation.finish()
            lock.withLock {
                self.continuation = nil
                self.stream = nil
            }
            throw SystemAudioTapError.streamSetupFailed(error.localizedDescription)
        }
        return buffers
    }

    public func stop() async {
        let (stream, continuation): (SCStream?, AsyncStream<AVAudioPCMBuffer>.Continuation?) = lock.withLock {
            let s = self.stream; self.stream = nil
            let c = self.continuation; self.continuation = nil
            return (s, c)
        }

        if let stream {
            try? await stream.stopCapture()
            try? stream.removeStreamOutput(self, type: .audio)
        }
        continuation?.finish()
    }

    // MARK: - SCStreamOutput (private queue)

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid,
              let pcm = Self.copyPCMBuffer(from: sampleBuffer) else { return }
        let continuation = lock.withLock { self.continuation }
        continuation?.yield(pcm)
    }

    // MARK: - SCStreamDelegate (delegate queue)

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        log.error("system-audio stream stopped: \(error.localizedDescription, privacy: .public)")
        let continuation = lock.withLock {
            let c = self.continuation; self.continuation = nil; return c
        }
        continuation?.finish()
    }

    // MARK: - Audio

    /// Deep-copies an SCK audio sample buffer into a freshly allocated PCM buffer.
    /// A copy (not a no-copy wrap of the block buffer) is required because the
    /// buffer outlives this callback — the transcriber consumes it asynchronously.
    private static func copyPCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return nil }
        var asbd = asbdPtr.pointee
        guard let format = AVAudioFormat(streamDescription: &asbd) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        pcm.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList)
        return status == noErr ? pcm : nil
    }
}
