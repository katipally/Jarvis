import Foundation
import GRDB
import JStore

/// The knowledge core: episodes in, facts + typed entities + bi-temporal edges
/// out, retrieval via fused lexical (FTS5 BM25) + semantic (cosine) + graph
/// signals. Replaces the old MemoryStore.
public struct KnowledgeStore: Sendable {
    public let database: JarvisDatabase
    private let embedder: Embedder

    public init(database: JarvisDatabase, embedder: Embedder = Embedder()) {
        self.database = database
        self.embedder = embedder
    }

    // MARK: - Worlds

    /// Idempotently register a world (data source).
    public func ensureWorld(id: String, kind: String, displayName: String, enabled: Bool) async {
        _ = try? await database.writer.write { db in
            if try WorldRow.fetchOne(db, key: id) == nil {
                try WorldRow(id: id, kind: kind, displayName: displayName, enabled: enabled).insert(db)
            }
        }
    }

    public func worlds() async -> [WorldRow] {
        (try? await database.reader.read { db in
            try WorldRow.order(Column("created_at")).fetchAll(db)
        }) ?? []
    }

    public func world(id: String) async -> WorldRow? {
        try? await database.reader.read { db in try WorldRow.fetchOne(db, key: id) }
    }

    public func setWorldEnabled(id: String, enabled: Bool) async {
        _ = try? await database.writer.write { db in
            try db.execute(sql: "UPDATE world SET enabled = ? WHERE id = ?", arguments: [enabled, id])
        }
    }

    public func updateWorldSync(id: String, cursorJson: String?, status: String, error: String? = nil, now: Date = .now) async {
        _ = try? await database.writer.write { db in
            try db.execute(sql: """
                UPDATE world SET cursor_json = COALESCE(?, cursor_json),
                                 last_sync_at = ?, last_status = ?, last_error = ? WHERE id = ?
                """, arguments: [cursorJson, now, status, error, id])
        }
    }

    // MARK: - Episodes

    /// Insert an episode; nil when (world, external_id) was already ingested —
    /// the unique key is what makes connector re-syncs idempotent. Real write
    /// failures THROW (they must not be mistaken for duplicates: callers use
    /// nil to mean "safe to advance cursors / mark sources done").
    @discardableResult
    public func addEpisode(worldId: String, externalId: String? = nil, occurredAt: Date,
                           title: String? = nil, content: String, now: Date = .now) async throws -> EpisodeRow? {
        let clean = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        return try await database.writer.write { db in
            let row = EpisodeRow(worldId: worldId, externalId: externalId, occurredAt: occurredAt,
                                 title: title, content: clean, createdAt: now)
            do {
                try row.insert(db)
                return row
            } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
                return nil // already ingested
            }
        }
    }

    /// Oldest pending episodes — the extraction queue (resume cursor at boot).
    public func pendingEpisodes(limit: Int = 10) async -> [EpisodeRow] {
        (try? await database.reader.read { db in
            try EpisodeRow
                .filter(Column("extraction_status") == "pending")
                .order(Column("occurred_at"))
                .limit(limit)
                .fetchAll(db)
        }) ?? []
    }

    public func markEpisode(id: String, status: String, now: Date = .now) async {
        _ = try? await database.writer.write { db in
            try db.execute(sql: "UPDATE episode SET extraction_status = ?, extracted_at = ? WHERE id = ?",
                           arguments: [status, now, id])
        }
    }

    // MARK: - Ingest runs (Activity feed bookkeeping)

    public func beginIngestRun(worldId: String, now: Date = .now) async -> String {
        let row = IngestRunRow(worldId: worldId, startedAt: now)
        _ = try? await database.writer.write { db in try row.insert(db) }
        return row.id
    }

    public func endIngestRun(id: String, status: String, episodes: Int, counts: IngestCounts,
                             error: String? = nil, now: Date = .now) async {
        _ = try? await database.writer.write { db in
            try db.execute(sql: """
                UPDATE ingest_run SET ended_at = ?, status = ?, episodes_added = ?,
                    facts_added = ?, entities_added = ?, edges_added = ?, error = ? WHERE id = ?
                """, arguments: [now, status, episodes, counts.facts, counts.entities, counts.edges, error, id])
        }
    }

    // MARK: - Ingest

    /// Write extraction output for an episode: validated facts (deduped three
    /// ways) + graph projection with functional supersession + invalidations.
    /// `bypassValidation` is the explicit `remember` path — a direct user
    /// instruction always wins.
    @discardableResult
    public func ingest(_ result: KnowledgeExtractionResult, episode: EpisodeRow?,
                       bypassValidation: Bool = false, now: Date = .now) async -> IngestCounts {
        // Per-episode caps: the 3B extractor occasionally floods; keep the top
        // slice by salience rather than trusting it to self-limit.
        let facts = result.facts
            .map { ExtractedFact(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), salience: $0.salience) }
            .filter { bypassValidation ? !$0.text.isEmpty : FactValidator.isDurable($0.text, source: episode?.content) }
            .sorted { $0.salience > $1.salience }
            .prefix(8)
        let entities = result.entities.filter { FactValidator.isRealEntity($0.name) }.prefix(10)
        let relations = result.relations.prefix(10)
        let invalidations = result.invalidations.prefix(5)

        // Embed OUTSIDE the write lock — NLContextualEmbedding inference must
        // not run while the single GRDB writer is held.
        let vectors = facts.map { embedder.embed($0.text) }
        let modelID = embedder.modelID

        let counts = (try? await database.writer.write { db -> IngestCounts in
            var counts = IngestCounts()
            var insertedFactIDs: [String] = []
            var presentFactIDs: [String] = [] // deduped-but-already-stored facts
            for (i, fact) in facts.enumerated() {
                // 1. exact duplicate already live — keep its id for provenance.
                if let existingID = try String.fetchOne(db, sql: """
                    SELECT id FROM fact WHERE superseded_by IS NULL AND LOWER(text) = ? LIMIT 1
                    """, arguments: [fact.text.lowercased()]) {
                    presentFactIDs.append(existingID)
                    continue
                }
                // 2. token-overlap near-dup vs FTS shortlist (Hive resolve.ts, 0.82)
                if let dupID = try Self.jaccardDuplicate(db, text: fact.text) {
                    presentFactIDs.append(dupID)
                    continue
                }
                // 3. semantic near-dup (paraphrase already stored, 0.92) —
                //    compared against the FTS shortlist's vectors only, not a
                //    full-table embedding scan.
                let vector = vectors[i]
                if let vector, try Self.isNearDuplicate(db, text: fact.text, vector: vector,
                                                        modelID: modelID, threshold: 0.92) { continue }

                let row = FactRow(episodeId: episode?.id, text: fact.text, salience: fact.salience, createdAt: now)
                try row.insert(db)
                if let vector {
                    try EmbeddingRow(ownerKind: "fact", ownerId: row.id, modelId: modelID,
                                     dim: vector.count, vector: Embedder.data(from: vector)).insert(db)
                }
                counts.facts += 1
                insertedFactIDs.append(row.id)
            }
            // Provenance representative for edges written this round: a fresh
            // fact if any, else an already-stored duplicate — so the remember()
            // path (fact stored in an earlier round) still yields provenance
            // and later invalidations can supersede it.
            let sourceFactId = insertedFactIDs.first ?? presentFactIDs.first

            // Entities → typed nodes.
            var idByNorm: [String: String] = [:]
            for entity in entities {
                let norm = EntityResolver.normName(entity.name)
                guard !norm.isEmpty,
                      let (id, created) = try GraphWriter.upsertEntity(db, name: entity.name, type: entity.type, now: now)
                else { continue }
                idByNorm[norm] = id
                if created { counts.entities += 1 }
            }

            func resolveEnd(_ name: String) throws -> String? {
                let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { return nil }
                if selfAliases.contains(clean.lowercased()) { return try GraphWriter.selfEntity(db, now: now) }
                guard FactValidator.isRealEntity(clean) else { return nil }
                if let known = idByNorm[EntityResolver.normName(clean)] { return known }
                guard let (id, created) = try GraphWriter.upsertEntity(db, name: clean, type: .thing, now: now) else { return nil }
                if created { counts.entities += 1 }
                idByNorm[EntityResolver.normName(clean)] = id
                return id
            }

            // Relations → edges (canonical verbs, functional supersession).
            for relation in relations {
                let rel = Relations.normalize(relation.relation)
                guard !rel.isEmpty,
                      let src = try resolveEnd(relation.subject),
                      let dst = try resolveEnd(relation.object),
                      src != dst else { continue }
                if try GraphWriter.upsertEdge(db, src: src, dst: dst, rel: rel,
                                              sourceFactId: sourceFactId,
                                              sourceEpisodeId: episode?.id,
                                              worldId: episode?.worldId, now: now) {
                    counts.edges += 1
                }
            }

            // Invalidations → close edges with no replacement (break-ups, quit).
            for inv in invalidations {
                let rel = Relations.normalize(inv.relation)
                let subjClean = inv.subject.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rel.isEmpty, !subjClean.isEmpty else { continue }
                let src: String?
                if selfAliases.contains(subjClean.lowercased()) {
                    src = try GraphWriter.selfEntity(db, now: now)
                } else {
                    src = try EntityRow
                        .filter(Column("norm") == EntityResolver.normName(subjClean))
                        .fetchOne(db)?.id
                }
                guard let src else { continue }
                let dst = inv.object.trimmingCharacters(in: .whitespacesAndNewlines)
                let dstID = dst.isEmpty ? nil : try EntityRow
                    .filter(Column("norm") == EntityResolver.normName(dst))
                    .fetchOne(db)?.id
                try GraphWriter.invalidate(db, src: src, rel: rel, dst: dstID, byFactId: sourceFactId, now: now)

                // Also retire the stored fact the invalidation contradicts —
                // edges without provenance (or facts stored in an earlier
                // round) would otherwise keep the stale text winning retrieval.
                // Best FTS match on "subject relation object", marked
                // superseded (kept, never deleted). Old free-text supersede,
                // structured.
                let phrase = [subjClean, rel.replacingOccurrences(of: "_", with: " "), dst]
                    .filter { !$0.isEmpty }.joined(separator: " ")
                if let staleID = try Self.jaccardBestMatch(db, phrase: phrase) {
                    try db.execute(sql: "UPDATE fact SET superseded_by = ? WHERE id = ? AND superseded_by IS NULL",
                                   arguments: [sourceFactId ?? staleID, staleID])
                }
            }

            return counts
        }) ?? IngestCounts()

        if counts.entities > 0 || counts.edges > 0 { Self.postGraphChange() }
        return counts
    }

    /// Best live-fact FTS match for an invalidation phrase (needs most of the
    /// phrase's tokens present — a loose OR match would retire innocents).
    static func jaccardBestMatch(_ db: Database, phrase: String) throws -> String? {
        let terms = queryTokens(phrase)
        guard terms.count >= 2 else { return nil }
        let match = terms.map { "\"\($0)\"" }.joined(separator: " OR ")
        let rows = try Row.fetchAll(db, sql: """
            SELECT fact.id AS id, fact.text AS text FROM fact
            JOIN fact_fts ON fact.rowid = fact_fts.rowid
            WHERE fact_fts MATCH ? AND fact.superseded_by IS NULL
            ORDER BY rank LIMIT 4
            """, arguments: [match])
        for row in rows {
            let text: String = row["text"]
            let overlap = Set(terms).intersection(queryTokens(text)).count
            if Double(overlap) / Double(terms.count) >= 0.6 { return row["id"] }
        }
        return nil
    }

    /// The id of an existing live fact whose token set overlaps ≥ 0.82 with
    /// this text (FTS shortlist) — an embedding-free paraphrase gate.
    static func jaccardDuplicate(_ db: Database, text: String) throws -> String? {
        let terms = queryTokens(text)
        guard !terms.isEmpty else { return nil }
        let match = terms.map { "\"\($0)\"" }.joined(separator: " OR ")
        let candidates = try Row.fetchAll(db, sql: """
            SELECT fact.id AS id, fact.text AS text FROM fact
            JOIN fact_fts ON fact.rowid = fact_fts.rowid
            WHERE fact_fts MATCH ? AND fact.superseded_by IS NULL
            ORDER BY rank LIMIT 8
            """, arguments: [match])
        for row in candidates where FactValidator.jaccard(text, row["text"]) >= 0.82 {
            return row["id"]
        }
        return nil
    }

    /// Semantic near-dup against the FTS shortlist's vectors only — dedup
    /// doesn't need (and mustn't pay for) a full-table embedding scan inside
    /// the write lock.
    static func isNearDuplicate(_ db: Database, text: String, vector: [Float],
                                modelID: String, threshold: Float) throws -> Bool {
        let terms = queryTokens(text)
        guard !terms.isEmpty else { return false }
        let match = terms.map { "\"\($0)\"" }.joined(separator: " OR ")
        let rows = try Row.fetchAll(db, sql: """
            SELECT embedding.vector AS vector FROM fact
            JOIN fact_fts ON fact.rowid = fact_fts.rowid
            JOIN embedding ON embedding.owner_id = fact.id
              AND embedding.owner_kind = 'fact' AND embedding.model_id = ?
            WHERE fact_fts MATCH ? AND fact.superseded_by IS NULL
            ORDER BY rank LIMIT 24
            """, arguments: [modelID, match])
        for row in rows {
            let data: Data = row["vector"]
            if Embedder.cosine(vector, Embedder.vector(from: data)) > threshold { return true }
        }
        return false
    }

    private static func postGraphChange() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .jarvisGraphDidChange, object: nil)
        }
    }

    // MARK: - Retrieval

    /// Fused lexical + semantic retrieval over live facts (RRF).
    public func retrieve(query: String, limit: Int = 8) async -> [RetrievedFact] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let queryVector = embedder.embed(trimmed)
        let modelID = embedder.modelID

        let (lexical, semantic) = (try? await database.reader.read { db -> ([String], [(String, Float)]) in
            let lexical = try Self.lexicalRanking(db, query: trimmed, limit: limit * 3)
            let semantic = try queryVector.map { try Self.semanticRanking(db, vector: $0, modelID: modelID, limit: limit * 3) } ?? []
            return (lexical, semantic)
        }) ?? ([], [])

        var scores: [String: Double] = [:]
        for (rank, id) in lexical.enumerated() { scores[id, default: 0] += 1.0 / Double(60 + rank) }
        for (rank, pair) in semantic.enumerated() { scores[pair.0, default: 0] += 1.0 / Double(60 + rank) }

        let topIDs = scores.sorted { $0.value > $1.value }.prefix(limit).map(\.key)
        guard !topIDs.isEmpty else { return [] }

        let rows = (try? await database.reader.read { db in
            try FactRow.filter(topIDs.contains(Column("id"))).fetchAll(db)
        }) ?? []
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        return topIDs.compactMap { id in
            guard let row = byID[id] else { return nil }
            return RetrievedFact(id: id, text: row.text, score: scores[id] ?? 0)
        }
    }

    static func lexicalRanking(_ db: Database, query: String, limit: Int) throws -> [String] {
        let terms = queryTokens(query)
        guard !terms.isEmpty else { return [] }
        let match = terms.map { "\"\($0)\"" }.joined(separator: " OR ")
        return try String.fetchAll(db, sql: """
            SELECT fact.id FROM fact
            JOIN fact_fts ON fact.rowid = fact_fts.rowid
            WHERE fact_fts MATCH ? AND fact.superseded_by IS NULL
            ORDER BY rank LIMIT ?
            """, arguments: [match, limit])
    }

    static func semanticRanking(_ db: Database, vector: [Float], modelID: String, limit: Int) throws -> [(String, Float)] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT embedding.owner_id AS id, embedding.vector AS vector FROM embedding
            JOIN fact ON fact.id = embedding.owner_id
            WHERE embedding.owner_kind = 'fact' AND embedding.model_id = ? AND fact.superseded_by IS NULL
            """, arguments: [modelID])
        var scored: [(String, Float)] = []
        scored.reserveCapacity(rows.count)
        for row in rows {
            let id: String = row["id"]
            let data: Data = row["vector"]
            scored.append((id, Embedder.cosine(vector, Embedder.vector(from: data))))
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map { $0 }
    }

    /// Graph-neighborhood lines for the query (hub-avoiding BFS).
    public func graphContext(for query: String, limit: Int = 8) async -> [String] {
        (try? await database.reader.read { db in
            try Traverse.graphFacts(db, query: query, limit: limit)
        }) ?? []
    }

    // MARK: - Facts UI

    public struct FactItem: Sendable, Identifiable {
        public let id: String
        public let text: String
        public let salience: Double
        public let createdAt: Date
        /// Where this memory came from — the source world's display name
        /// ("Mail", "Calendar", "Conversation"…), or nil if unknown. Provenance.
        public var source: String?
    }

    /// Live facts, newest first.
    public func list(limit: Int = 200) async -> [FactItem] {
        (try? await database.reader.read { db -> [FactItem] in
            let facts = try FactRow
                .filter(Column("superseded_by") == nil)
                .order(Column("created_at").desc)
                .limit(limit)
                .fetchAll(db)
            // Provenance: fact → source episode → world display name, in two
            // batched lookups (no N+1).
            let episodeIDs = Set(facts.compactMap { $0.episodeId })
            var worldByEpisode: [String: String] = [:]
            if !episodeIDs.isEmpty {
                for e in try EpisodeRow.filter(keys: episodeIDs).fetchAll(db) {
                    worldByEpisode[e.id] = e.worldId
                }
            }
            var nameByWorld: [String: String] = [:]
            let worldIDs = Set(worldByEpisode.values)
            if !worldIDs.isEmpty {
                for w in try WorldRow.filter(keys: worldIDs).fetchAll(db) {
                    nameByWorld[w.id] = w.displayName
                }
            }
            return facts.map { f in
                let source = f.episodeId.flatMap { worldByEpisode[$0] }.flatMap { nameByWorld[$0] }
                return FactItem(id: f.id, text: f.text, salience: f.salience, createdAt: f.createdAt, source: source)
            }
        }) ?? []
    }

    /// Edit a fact's text and re-embed it.
    public func update(id: String, text: String, now: Date = .now) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let vector = embedder.embed(clean)
        let modelID = embedder.modelID
        _ = try? await database.writer.write { db in
            try db.execute(sql: "UPDATE fact SET text = ? WHERE id = ?", arguments: [clean, id])
            try db.execute(sql: "DELETE FROM embedding WHERE owner_kind = 'fact' AND owner_id = ?", arguments: [id])
            if let vector {
                try EmbeddingRow(ownerKind: "fact", ownerId: id, modelId: modelID,
                                 dim: vector.count, vector: Embedder.data(from: vector)).insert(db)
            }
        }
    }

    /// Forget a fact — tombstoned by pointing superseded_by at itself (kept for
    /// audit, out of retrieval, no separate status column needed).
    public func archive(id: String) async {
        _ = try? await database.writer.write { db in
            try db.execute(sql: "UPDATE fact SET superseded_by = id WHERE id = ?", arguments: [id])
        }
    }

    // MARK: - Maintenance

    /// Boot task: embed live facts lacking a current-model vector; drop vectors
    /// from other model ids (a model upgrade changes the dimension).
    public func reembedMissing() async {
        guard embedder.isAvailable else { return }
        let modelID = embedder.modelID
        let toEmbed: [(id: String, text: String)] = (try? await database.writer.write { db -> [(id: String, text: String)] in
            try db.execute(sql: "DELETE FROM embedding WHERE owner_kind = 'fact' AND model_id <> ?",
                           arguments: [modelID])
            let rows = try Row.fetchAll(db, sql: """
                SELECT fact.id AS id, fact.text AS text FROM fact
                WHERE fact.superseded_by IS NULL AND NOT EXISTS (
                    SELECT 1 FROM embedding
                    WHERE embedding.owner_kind = 'fact'
                      AND embedding.owner_id = fact.id
                      AND embedding.model_id = ?)
                """, arguments: [modelID])
            return rows.map { (id: $0["id"], text: $0["text"]) }
        }) ?? []
        guard !toEmbed.isEmpty else { return }

        let inserts: [(String, [Float])] = toEmbed.compactMap { row in
            embedder.embed(row.text).map { (row.id, $0) }
        }
        guard !inserts.isEmpty else { return }
        _ = try? await database.writer.write { db in
            for (id, vector) in inserts {
                try EmbeddingRow(ownerKind: "fact", ownerId: id, modelId: modelID,
                                 dim: vector.count, vector: Embedder.data(from: vector)).insert(db)
            }
        }
    }

    /// Debug counters for the Settings pane.
    public struct Stats: Sendable {
        public var episodesPending = 0
        public var episodesDone = 0
        public var facts = 0
        public var entities = 0
        public var edges = 0
        /// False when on-device embedding assets aren't ready — recall is
        /// keyword-only until they download. Surfaced in Settings.
        public var semanticAvailable = true
    }

    public func stats() async -> Stats {
        var s = (try? await database.reader.read { db in
            var s = Stats()
            s.episodesPending = try EpisodeRow.filter(Column("extraction_status") == "pending").fetchCount(db)
            s.episodesDone = try EpisodeRow.filter(Column("extraction_status") == "done").fetchCount(db)
            s.facts = try FactRow.filter(Column("superseded_by") == nil).fetchCount(db)
            s.entities = try EntityRow.fetchCount(db)
            s.edges = try EdgeRow.filter(Column("invalidated_at") == nil).fetchCount(db)
            return s
        }) ?? Stats()
        s.semanticAvailable = embedder.semanticAvailable
        return s
    }
}

public extension Notification.Name {
    /// Posted after an ingest adds graph nodes/relations so the graph/facts UI
    /// can reload instead of polling.
    static let jarvisGraphDidChange = Notification.Name("jarvisGraphDidChange")
}
