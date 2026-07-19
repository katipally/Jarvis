import Foundation
import GRDB
import Testing
@testable import JMemory
@testable import JStore

private func makeStore() throws -> (MemoryStore, JarvisDatabase) {
    let db = try JarvisDatabase.inMemory()
    return (MemoryStore(database: db), db)
}

@Test func embedderProducesUnitVectors() {
    let embedder = Embedder()
    guard embedder.isAvailable else { return } // skip if the OS model is missing
    guard let v = embedder.embed("the cat sat on the mat") else { return }
    let norm = Embedder.cosine(v, v)
    #expect(abs(norm - 1.0) < 0.01) // self-similarity of a unit vector is 1
}

@Test func vectorDataRoundTrips() {
    let original: [Float] = [0.1, -0.2, 0.3, 0.44]
    let data = Embedder.data(from: original)
    let back = Embedder.vector(from: data)
    #expect(back == original)
}

@Test func ingestAndLexicalRetrieval() async throws {
    let (store, _) = try makeStore()
    let result = ExtractionResult(memories: [
        ExtractedMemory(kind: .fact, text: "Yash is building a macOS notch assistant called Jarvis"),
        ExtractedMemory(kind: .preference, text: "Yash prefers concise answers"),
        ExtractedMemory(kind: .fact, text: "The capital of France is Paris"),
    ])
    await store.ingest(result, segmentID: "s1")

    let hits = await store.retrieve(query: "what is Yash building", limit: 3)
    #expect(hits.contains { $0.text.contains("Jarvis") })
}

@Test func ingestDeduplicatesExactMemories() async throws {
    let (store, db) = try makeStore()
    let m = ExtractedMemory(kind: .fact, text: "Yash lives in Seattle")
    await store.ingest(ExtractionResult(memories: [m]), segmentID: "s1")
    await store.ingest(ExtractionResult(memories: [m]), segmentID: "s2")
    let count = try await db.reader.read { db in try MemoryRow.filter(Column("status") == "active").fetchCount(db) }
    #expect(count == 1)
}

@Test func graphSupersedesFunctionalRelation() async throws {
    let (store, db) = try makeStore()
    await store.ingest(ExtractionResult(
        entities: [ExtractedEntity(name: "Yash", kind: "person"), ExtractedEntity(name: "Seattle", kind: "place")],
        relations: [ExtractedRelation(subject: "Yash", relation: "lives_in", object: "Seattle")]
    ), segmentID: "s1")

    await store.ingest(ExtractionResult(
        entities: [ExtractedEntity(name: "Yash", kind: "person"), ExtractedEntity(name: "San Francisco", kind: "place")],
        relations: [ExtractedRelation(subject: "Yash", relation: "lives_in", object: "San Francisco")]
    ), segmentID: "s2")

    let (active, closed) = try await db.reader.read { db -> (Int, Int) in
        let active = try GraphEdgeRow.filter(Column("relation") == "lives_in" && Column("valid_to") == nil).fetchCount(db)
        let closed = try GraphEdgeRow.filter(Column("relation") == "lives_in" && Column("valid_to") != nil).fetchCount(db)
        return (active, closed)
    }
    // Both eras retained: one active (San Francisco), one closed (Seattle).
    #expect(active == 1)
    #expect(closed == 1)
}

@Test func graphContextReturnsRelations() async throws {
    let (store, _) = try makeStore()
    await store.ingest(ExtractionResult(
        entities: [ExtractedEntity(name: "Jarvis", kind: "project"), ExtractedEntity(name: "Swift", kind: "topic")],
        relations: [ExtractedRelation(subject: "Jarvis", relation: "uses", object: "Swift")]
    ), segmentID: "s1")
    let lines = await store.graphContext(for: "tell me about Jarvis")
    #expect(lines.contains { $0.contains("Jarvis") && $0.contains("Swift") })
}

@Test func consolidatePromotesShortToLong() async throws {
    let (store, db) = try makeStore()
    await store.ingest(ExtractionResult(memories: [ExtractedMemory(kind: .fact, text: "test fact")]), segmentID: "s1")
    await store.consolidate(olderThan: 0)
    let longCount = try await db.reader.read { db in try MemoryRow.filter(Column("tier") == "long").fetchCount(db) }
    #expect(longCount == 1)
}
