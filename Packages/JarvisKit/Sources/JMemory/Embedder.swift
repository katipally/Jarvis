import Accelerate
import Foundation
@preconcurrency import NaturalLanguage

/// On-device sentence embeddings via Apple's NaturalLanguage framework.
/// Produces a fixed-dimension vector per text; cosine similarity via Accelerate.
/// `NLEmbedding` is a read-only model, safe to share across threads.
public struct Embedder: @unchecked Sendable {
    public let modelID: String
    private let embedding: NLEmbedding?

    public init(language: NLLanguage = .english) {
        self.embedding = NLEmbedding.sentenceEmbedding(for: language)
        self.modelID = "nl-sentence-\(language.rawValue)"
    }

    public var isAvailable: Bool { embedding != nil }
    public var dimension: Int { embedding?.dimension ?? 0 }

    /// Embed text to a unit-normalized Float vector, or nil if unavailable.
    public func embed(_ text: String) -> [Float]? {
        guard let embedding, let vector = embedding.vector(for: text.lowercased()) else { return nil }
        var floats = vector.map(Float.init)
        Self.normalize(&floats)
        return floats
    }

    // MARK: - Vector <-> Data (Float32 little-endian)

    public static func data(from vector: [Float]) -> Data {
        vector.withUnsafeBytes { Data($0) }
    }

    public static func vector(from data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.size
        return data.withUnsafeBytes { raw in
            Array(UnsafeBufferPointer(start: raw.bindMemory(to: Float.self).baseAddress, count: count))
        }
    }

    // MARK: - Math

    /// Cosine similarity for unit vectors reduces to a dot product.
    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var result: Float = 0
        vDSP_dotpr(a, 1, b, 1, &result, vDSP_Length(a.count))
        return result
    }

    static func normalize(_ v: inout [Float]) {
        var norm: Float = 0
        vDSP_svesq(v, 1, &norm, vDSP_Length(v.count))
        norm = norm.squareRoot()
        guard norm > 0 else { return }
        var inv = 1 / norm
        vDSP_vsmul(v, 1, &inv, &v, 1, vDSP_Length(v.count))
    }
}
