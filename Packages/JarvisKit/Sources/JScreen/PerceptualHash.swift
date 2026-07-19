import CoreGraphics
import Foundation

/// 64-bit average hash (aHash): downscale to 8×8 grayscale, bit = pixel ≥ mean.
/// Hamming distance measures visual similarity for dedup.
public enum PerceptualHash {
    public static func averageHash(_ image: CGImage) -> Int64 {
        let size = 8
        var pixels = [UInt8](repeating: 0, count: size * size)
        let gray = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: &pixels, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: size, space: gray, bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0 }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

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
