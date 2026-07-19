import CoreGraphics
import Foundation

/// 64-bit average hash (aHash): downscale to 8×8 grayscale, bit = pixel ≥ mean.
/// Hamming distance measures visual similarity for dedup.
public enum PerceptualHash {
    public static func averageHash(_ image: CGImage) -> Int64 {
        let size = 8
        var pixels = [UInt8](repeating: 0, count: size * size)
        let gray = CGColorSpaceCreateDeviceGray()
        // The pixel pointer must stay valid for the context's whole lifetime,
        // not just the initializer call — keep all use inside the closure.
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8,
                bytesPerRow: size, space: gray, bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            ctx.interpolationQuality = .low
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard drew else { return 0 }

        let mean = pixels.reduce(0) { $0 + Int($1) } / (size * size)
        var hash: Int64 = 0
        for (i, pixel) in pixels.enumerated() where Int(pixel) >= mean {
            hash |= (Int64(1) << Int64(i))
        }
        return hash
    }

    public static func hamming(_ a: Int64, _ b: Int64) -> Int {
        (a ^ b).nonzeroBitCount
    }
}
