import Foundation
import ImageIO
import Vision

/// Apple Vision OCR over a captured screen JPEG. Vision delivers its results on a
/// private queue, so all completion handling here is @Sendable-safe and bridged to
/// async via a checked continuation. Returns "" on any failure — the caller marks
/// the frame `done` with empty text rather than retrying a frame that will never OCR.
public enum FrameOCR {
    /// OCR a JPEG on disk. Recognized lines are joined with newlines.
    public static func text(jpegPath: String) async -> String {
        guard let cgImage = loadCGImage(path: jpegPath) else { return "" }
        return await text(cgImage: cgImage)
    }

    /// OCR a CGImage directly.
    public static func text(cgImage: CGImage) async -> String {
        await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            let request = VNRecognizeTextRequest { @Sendable request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                // Defensive copy — Vision's bridged NSArray results can trip
                // EXC_BREAKPOINT/SIGTRAP if the backing buffer is released while it's
                // still being enumerated on Vision's private queue.
                let lines = Array(observations).compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // Automatic language selection — avoids pinning a recognitionLanguages
            // array (whose storage lifetime is the SIGTRAP hazard) altogether.
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: "")
            }
        }
    }

    private static func loadCGImage(path: String) -> CGImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
