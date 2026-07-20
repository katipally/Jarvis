import Accelerate
import Foundation
@preconcurrency import NaturalLanguage

/// On-device sentence embeddings via Apple's `NLContextualEmbedding` (BERT-class
/// contextual model). A sentence vector is produced by MEAN-POOLING the model's
/// per-token vectors, then unit-normalizing so cosine similarity is a dot product.
/// The model is loaded lazily on first use (loading is expensive) and its assets
/// are downloaded over-the-air, so when they aren't present `embed()` returns nil
/// and retrieval degrades to FTS-only (handled in KnowledgeStore).
public struct Embedder: @unchecked Sendable {
    public let modelID: String
    private let model: Model?

    public init(language: NLLanguage = .english) {
        self.model = NLContextualEmbedding(language: language).map { Model(embedding: $0, language: language) }
        // Bumped from the old NLEmbedding id so a boot re-embed replaces the
        // old (differently-dimensioned) vectors — see KnowledgeStore.reembedMissing().
        self.modelID = "nl-contextual-v1"
    }

    public var isAvailable: Bool { model != nil }
    public var dimension: Int { model?.dimension ?? 0 }

    /// Embed text to a unit-normalized Float vector, or nil if the model / its
    /// assets are unavailable or the text produced no tokens.
    public func embed(_ text: String) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let model, var floats = model.meanPooledVector(for: trimmed) else { return nil }
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

/// Reference-type holder so an immutable, shared `Embedder` can lazily load the
/// (expensive) contextual model exactly once and serialize inference — the
/// underlying model isn't documented as concurrency-safe.
private final class Model: @unchecked Sendable {
    private let embedding: NLContextualEmbedding
    private let language: NLLanguage
    private let lock = NSLock()
    /// nil = not yet loaded, true = loaded, false = load failed / assets missing.
    private var loaded: Bool?

    let dimension: Int

    init(embedding: NLContextualEmbedding, language: NLLanguage) {
        self.embedding = embedding
        self.language = language
        self.dimension = embedding.dimension
    }

    /// Mean-pool the per-token contextual vectors into one sentence vector.
    func meanPooledVector(for text: String) -> [Float]? {
        lock.lock()
        defer { lock.unlock() }
        guard ensureLoaded(),
              let result = try? embedding.embeddingResult(for: text, language: language) else { return nil }

        var sum = [Double](repeating: 0, count: dimension)
        var count = 0
        result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { tokenVector, _ in
            let n = min(tokenVector.count, sum.count)
            for i in 0..<n { sum[i] += tokenVector[i] }
            count += 1
            return true
        }
        guard count > 0 else { return nil }
        return sum.map { Float($0 / Double(count)) }
    }

    /// Load the model on first use; assets download over-the-air, so this fails
    /// (and we stay `false`) when they aren't on device.
    private func ensureLoaded() -> Bool {
        if let loaded { return loaded }
        guard embedding.hasAvailableAssets else { loaded = false; return false }
        do {
            try embedding.load()
            loaded = true
        } catch {
            loaded = false
        }
        return loaded ?? false
    }
}
