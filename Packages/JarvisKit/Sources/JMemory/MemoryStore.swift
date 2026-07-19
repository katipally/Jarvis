import Foundation
import GRDB
import JStore

/// The local memory system: writes extracted memories + a temporal knowledge
/// graph, embeds for semantic search, and retrieves via fused lexical (FTS5
/// BM25) + semantic (cosine) + graph-neighborhood signals.
public struct MemoryStore: Sendable {
    private let database: JarvisDatabase
    private let embedder: Embedder

    public init(database: JarvisDatabase, embedder: Embedder = Embedder()) {
        self.database = database
        self.embedder = embedder
    }

    // MARK: - Ingest

    /// Write extraction output: memories (short-term) + graph projection.
    public func ingest(_ result: ExtractionResult, segmentID: String?, now: Date = .now) async {
        // Embed candidate texts OUTSIDE the write lock — NLContextualEmbedding
        // inference must not run while the single GRDB writer is held (mirrors
        // reembedMissing). Only the inserts below are transacted.
        let vectors = result.memories.map {
            embedder.embed($0.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let graphChanged = (try? await database.writer.write { db -> Bool in
            for (i, memory) in result.memories.enumerated() {
                let clean = memory.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { continue }
                // Skip exact duplicates already active.
                let exists = try MemoryRow
                    .filter(Column("status") == "active")
                    .filter(sql: "LOWER(text) = ?", arguments: [clean.lowercased()])
                    .fetchCount(db) > 0
                if exists { continue }

                // Semantic near-duplicate: skip when a paraphrase is already stored.
                let vector = vectors[i]
                if let vector, try isNearDuplicate(db, vector: vector, threshold: 0.92) { continue }

                let row = MemoryRow(
                    tier: "short", kind: memory.kind.rawValue, text: clean,
                    importance: memory.importance, sourceSegmentId: segmentID, createdAt: now, updatedAt: now
                )
                try row.insert(db)
                if let vector {
                    try EmbeddingRow(
                        ownerKind: "memory", ownerId: row.id, modelId: embedder.modelID,
                        dim: vector.count, vector: Embedder.data(from: vector)
                    ).insert(db)
                }
            }

            // Entities → nodes (alias-resolved).
            var nodeIDs: [String: String] = [:] // normalized name → node id
            for entity in result.entities {
                let norm = normalizeText(entity.name)
                guard !norm.isEmpty else { continue }
                nodeIDs[norm] = try resolveOrCreateNode(db, name: entity.name, norm: norm, kind: entity.kind, now: now)
            }

            // Relations → edges with temporal validity.
            for relation in result.relations {
                let subjNorm = normalizeText(relation.subject)
                let objNorm = normalizeText(relation.object)
                guard !subjNorm.isEmpty, !objNorm.isEmpty else { continue }
                let src = try nodeIDs[subjNorm] ?? resolveOrCreateNode(db, name: relation.subject, norm: subjNorm, kind: "topic", now: now)
                let dst = try nodeIDs[objNorm] ?? resolveOrCreateNode(db, name: relation.object, norm: objNorm, kind: "topic", now: now)
                nodeIDs[subjNorm] = src
                nodeIDs[objNorm] = dst
                try upsertEdge(db, src: src, dst: dst, relation: relation.relation, now: now)
            }
            return !result.entities.isEmpty || !result.relations.isEmpty
        }) ?? false

        // Nudge the graph/memory UI to reload after nodes or relations land.
        if graphChanged { Self.postGraphChange() }
    }

    /// Post on the main actor so SwiftUI observers mutate view state safely.
    private static func postGraphChange() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .jarvisGraphDidChange, object: nil)
        }
    }

    private func resolveOrCreateNode(_ db: Database, name: String, norm: String, kind: String, now: Date) throws -> String {
        if let node = try GraphNodeRow.filter(Column("name_norm") == norm).filter(Column("valid_to") == nil).fetchOne(db) {
            return node.id
        }
        if let alias = try NodeAliasRow.filter(Column("alias_norm") == norm).fetchOne(db) {
            return alias.nodeId
        }
        let node = GraphNodeRow(kind: kind, name: name, nameNorm: norm, validFrom: now, createdAt: now)
        try node.insert(db)
        try NodeAliasRow(nodeId: node.id, alias: name, aliasNorm: norm).insert(db)
        return node.id
    }

    private func upsertEdge(_ db: Database, src: String, dst: String, relation: String, now: Date) throws {
        // Same edge already active → nothing to do.
        let existing = try GraphEdgeRow
            .filter(Column("src_id") == src && Column("relation") == relation && Column("valid_to") == nil)
            .fetchAll(db)
        if existing.contains(where: { $0.dstId == dst }) { return }

        // Functional relation changing value → close the old edge(s).
        if functionalRelations.contains(relation) {
            for var old in existing {
                old.validTo = now
                try old.update(db)
            }
        }
        try GraphEdgeRow(srcId: src, dstId: dst, relation: relation, validFrom: now, createdAt: now).insert(db)
    }

    // MARK: - Retrieval

    /// Fused lexical + semantic retrieval over active memories.
    public func retrieve(query: String, limit: Int = 8) async -> [RetrievedMemory] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let queryVector = embedder.embed(trimmed)

        let (lexical, semantic) = (try? await database.reader.read { db -> ([String], [(String, Float)]) in
            let lexical = try lexicalRanking(db, query: trimmed, limit: limit * 3)
            let semantic = try queryVector.map { try semanticRanking(db, vector: $0, limit: limit * 3) } ?? []
            return (lexical, semantic)
        }) ?? ([], [])

        // Reciprocal-rank fusion.
        var scores: [String: Double] = [:]
        for (rank, id) in lexical.enumerated() { scores[id, default: 0] += 1.0 / Double(60 + rank) }
        for (rank, pair) in semantic.enumerated() { scores[pair.0, default: 0] += 1.0 / Double(60 + rank) }

        let topIDs = scores.sorted { $0.value > $1.value }.prefix(limit).map(\.key)
        guard !topIDs.isEmpty else { return [] }

        let rows = (try? await database.reader.read { db in
            try MemoryRow.filter(topIDs.contains(Column("id"))).fetchAll(db)
        }) ?? []
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        return topIDs.compactMap { id in
            guard let row = byID[id] else { return nil }
            return RetrievedMemory(id: id, text: row.text, kind: row.kind, score: scores[id] ?? 0)
        }
    }

    private func lexicalRanking(_ db: Database, query: String, limit: Int) throws -> [String] {
        let terms = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
        guard !terms.isEmpty else { return [] }
        let match = terms.map { "\"\($0)\"" }.joined(separator: " OR ")
        return try String.fetchAll(db, sql: """
            SELECT memory.id FROM memory
            JOIN memory_fts ON memory.rowid = memory_fts.rowid
            WHERE memory_fts MATCH ? AND memory.status = 'active'
            ORDER BY rank LIMIT ?
            """, arguments: [match, limit])
    }

    private func semanticRanking(_ db: Database, vector: [Float], limit: Int) throws -> [(String, Float)] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT embedding.owner_id AS id, embedding.vector AS vector FROM embedding
            JOIN memory ON memory.id = embedding.owner_id
            WHERE embedding.owner_kind = 'memory' AND memory.status = 'active'
            """)
        var scored: [(String, Float)] = []
        scored.reserveCapacity(rows.count)
        for row in rows {
            let id: String = row["id"]
            let data: Data = row["vector"]
            let candidate = Embedder.vector(from: data)
            scored.append((id, Embedder.cosine(vector, candidate)))
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map { $0 }
    }

    /// True when `vector` is within the dedup threshold of an active memory's
    /// current-model embedding — i.e. a paraphrase we already know.
    private func isNearDuplicate(_ db: Database, vector: [Float], threshold: Float) throws -> Bool {
        let rows = try Row.fetchAll(db, sql: """
            SELECT embedding.vector AS vector FROM embedding
            JOIN memory ON memory.id = embedding.owner_id
            WHERE embedding.owner_kind = 'memory' AND embedding.model_id = ? AND memory.status = 'active'
            """, arguments: [embedder.modelID])
        for row in rows {
            let data: Data = row["vector"]
            if Embedder.cosine(vector, Embedder.vector(from: data)) > threshold { return true }
        }
        return false
    }

    /// Relation lines for entities mentioned in the query (graph neighborhood).
    public func graphContext(for query: String, limit: Int = 6) async -> [String] {
        let terms = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
        guard !terms.isEmpty else { return [] }

        return (try? await database.reader.read { db -> [String] in
            var lines: [String] = []
            for term in terms {
                let nodes = try GraphNodeRow
                    .filter(sql: "name_norm LIKE ? AND valid_to IS NULL", arguments: ["%\(term)%"])
                    .limit(3).fetchAll(db)
                for node in nodes {
                    let edges = try GraphEdgeRow
                        .filter(Column("src_id") == node.id && Column("valid_to") == nil)
                        .limit(4).fetchAll(db)
                    for edge in edges {
                        if let dst = try GraphNodeRow.fetchOne(db, key: edge.dstId) {
                            lines.append("\(node.name) \(edge.relation.replacingOccurrences(of: "_", with: " ")) \(dst.name)")
                        }
                    }
                }
                if lines.count >= limit { break }
            }
            return Array(Set(lines).prefix(limit))
        }) ?? []
    }

    // MARK: - Consolidation

    /// Promote surviving short-term memories to long-term; mark them accessed.
    public func consolidate(olderThan age: TimeInterval = 0, now: Date = .now) async {
        _ = try? await database.writer.write { db in
            let cutoff = now.addingTimeInterval(-age)
            let shortTerm = try MemoryRow
                .filter(Column("tier") == "short" && Column("status") == "active")
                .filter(Column("created_at") <= cutoff)
                .fetchAll(db)
            for var memory in shortTerm {
                memory.tier = "long"
                memory.updatedAt = now
                try memory.update(db)
            }
        }
    }

    public func touch(ids: [String], now: Date = .now) async {
        guard !ids.isEmpty else { return }
        _ = try? await database.writer.write { db in
            try db.execute(sql: """
                UPDATE memory SET access_count = access_count + 1, last_accessed_at = ?
                WHERE id IN (\(ids.map { _ in "?" }.joined(separator: ",")))
                """, arguments: StatementArguments([now] + ids))
        }
    }

    // MARK: - Maintenance

    /// Boot task: embed active memories that lack a vector for the current model,
    /// and drop vectors from other model ids (a model upgrade changes the
    /// dimension, so old rows are unusable). Inference runs outside the write
    /// lock; only the inserts are transacted.
    public func reembedMissing() async {
        guard embedder.isAvailable else { return }
        let toEmbed: [(id: String, text: String)] = (try? await database.writer.write { db -> [(id: String, text: String)] in
            try db.execute(sql: "DELETE FROM embedding WHERE owner_kind = 'memory' AND model_id <> ?",
                           arguments: [embedder.modelID])
            let rows = try Row.fetchAll(db, sql: """
                SELECT memory.id AS id, memory.text AS text FROM memory
                WHERE memory.status = 'active' AND NOT EXISTS (
                    SELECT 1 FROM embedding
                    WHERE embedding.owner_kind = 'memory'
                      AND embedding.owner_id = memory.id
                      AND embedding.model_id = ?)
                """, arguments: [embedder.modelID])
            return rows.map { row in
                let id: String = row["id"]
                let text: String = row["text"]
                return (id: id, text: text)
            }
        }) ?? []
        guard !toEmbed.isEmpty else { return }

        let inserts: [(String, [Float])] = toEmbed.compactMap { row in
            embedder.embed(row.text).map { (row.id, $0) }
        }
        guard !inserts.isEmpty else { return }
        _ = try? await database.writer.write { db in
            for (id, vector) in inserts {
                try EmbeddingRow(ownerKind: "memory", ownerId: id, modelId: embedder.modelID,
                                 dim: vector.count, vector: Embedder.data(from: vector)).insert(db)
            }
        }
    }

    /// Retire active memories that an invalidation phrase makes false — the best
    /// FTS match per phrase is marked `superseded` (kept, never deleted).
    public func supersede(matching phrases: [String], now: Date = .now) async {
        let clean = phrases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !clean.isEmpty else { return }
        _ = try? await database.writer.write { db in
            for phrase in clean {
                let terms = phrase.lowercased()
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { $0.count > 2 }
                guard !terms.isEmpty else { continue }
                let match = terms.map { "\"\($0)\"" }.joined(separator: " OR ")
                let ids = try String.fetchAll(db, sql: """
                    SELECT memory.id FROM memory
                    JOIN memory_fts ON memory.rowid = memory_fts.rowid
                    WHERE memory_fts MATCH ? AND memory.status = 'active'
                    ORDER BY rank LIMIT 1
                    """, arguments: [match])
                for id in ids {
                    try db.execute(sql: "UPDATE memory SET status = 'superseded', updated_at = ? WHERE id = ?",
                                   arguments: [now, id])
                }
            }
        }
    }

    // MARK: - Memories UI

    /// One active memory for the Memories pane.
    public struct MemoryItem: Sendable, Identifiable {
        public let id: String
        public let kind: String
        public let text: String
        public let createdAt: Date
        public let updatedAt: Date
    }

    /// Active memories, most-recently-touched first.
    public func list(limit: Int = 200) async -> [MemoryItem] {
        (try? await database.reader.read { db in
            try MemoryRow
                .filter(Column("status") == "active")
                .order(Column("updated_at").desc)
                .limit(limit)
                .fetchAll(db)
                .map { MemoryItem(id: $0.id, kind: $0.kind, text: $0.text, createdAt: $0.createdAt, updatedAt: $0.updatedAt) }
        }) ?? []
    }

    /// Rename a memory's text and re-embed it.
    public func update(id: String, text: String, now: Date = .now) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let vector = embedder.embed(clean)
        _ = try? await database.writer.write { db in
            guard var row = try MemoryRow.fetchOne(db, key: id) else { return }
            row.text = clean
            row.updatedAt = now
            try row.update(db)
            try db.execute(sql: "DELETE FROM embedding WHERE owner_kind = 'memory' AND owner_id = ?", arguments: [id])
            if let vector {
                try EmbeddingRow(ownerKind: "memory", ownerId: id, modelId: embedder.modelID,
                                 dim: vector.count, vector: Embedder.data(from: vector)).insert(db)
            }
        }
    }

    /// Forget a memory (soft delete — kept as `archived`, out of retrieval).
    public func archive(id: String, now: Date = .now) async {
        _ = try? await database.writer.write { db in
            try db.execute(sql: "UPDATE memory SET status = 'archived', updated_at = ? WHERE id = ?",
                           arguments: [now, id])
        }
    }
}

public extension Notification.Name {
    /// Posted after an ingest adds graph nodes/relations so the graph/memory UI
    /// can reload instead of polling.
    static let jarvisGraphDidChange = Notification.Name("jarvisGraphDidChange")
}
