import Foundation
import GRDB
import JStore

/// Write-side graph operations (Hive write.ts port). All functions run inside
/// the caller's transaction; none of them touch the LLM or the embedder.
public enum GraphWriter {
    /// Get-or-create the single is_self "Me" person node.
    public static func selfEntity(_ db: Database, now: Date = .now) throws -> String {
        if let existing = try EntityRow.filter(Column("is_self") == true).fetchOne(db) {
            return existing.id
        }
        let norm = EntityResolver.normName("Me")
        let row = EntityRow(id: EntityResolver.deterministicID(type: .person, norm: norm),
                            type: EntityType.person.rawValue, name: "Me", norm: norm,
                            isSelf: true, createdAt: now)
        try row.insert(db)
        return row.id
    }

    /// Resolve a name+type to an entity id, creating the entity if it's new.
    /// Self-references collapse into the is_self node. New names that fuzzy-
    /// match an existing entity are recorded as aliases of it. nil = the name
    /// normalizes to nothing (emoji/punctuation-only) — skip, don't abort.
    public static func upsertEntity(_ db: Database, name: String, type: EntityType,
                                    now: Date = .now) throws -> (id: String, created: Bool)? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if selfAliases.contains(clean.lowercased()) {
            return (try selfEntity(db, now: now), false)
        }
        let norm = EntityResolver.normName(clean)
        guard !norm.isEmpty else { return nil }

        if let existing = try EntityResolver.resolveExisting(db, name: clean, type: type) {
            // A fuzzy/variant hit — remember the spelling as an alias for next time.
            try EntityAliasRow(entityId: existing, alias: clean, aliasNorm: norm)
                .insert(db, onConflict: .ignore)
            return (existing, false)
        }

        let row = EntityRow(id: EntityResolver.deterministicID(type: type, norm: norm),
                            type: type.rawValue, name: clean, norm: norm, createdAt: now)
        try row.insert(db)
        try EntityAliasRow(entityId: row.id, alias: clean, aliasNorm: norm).insert(db, onConflict: .ignore)
        return (row.id, true)
    }

    /// Insert an edge with functional-relation supersession. Returns true when
    /// a new edge was written (false = identical live edge already present).
    @discardableResult
    public static func upsertEdge(_ db: Database, src: String, dst: String, rel: String,
                                  confidence: Double = 0.8, sourceFactId: String? = nil,
                                  sourceEpisodeId: String? = nil, worldId: String? = nil,
                                  validFrom: Date? = nil, validTo: Date? = nil, now: Date = .now) throws -> Bool {
        let live = try EdgeRow
            .filter(Column("src_id") == src && Column("rel") == rel)
            .filter(Column("invalidated_at") == nil)
            .fetchAll(db)
        if live.contains(where: { $0.dstId == dst }) { return false }

        let edge = EdgeRow(srcId: src, dstId: dst, rel: rel, confidence: confidence,
                           validFrom: validFrom ?? now, validTo: validTo, createdAt: now,
                           sourceFactId: sourceFactId, sourceEpisodeId: sourceEpisodeId,
                           worldId: worldId)
        try edge.insert(db)

        // Functional relation changing value → close the old edge(s), keep history.
        if Relations.isFunctional(rel) {
            try invalidate(db, src: src, rel: rel, byFactId: sourceFactId,
                           exceptEdgeId: edge.id, supersededBy: edge.id, now: now)
        }
        return true
    }

    /// Close live edges matching src+rel (optionally only to `dst`), marking
    /// them invalidated — never deleted. Also supersedes the raw facts that
    /// sourced them (Hive DATA-1) so the stale fact stops surfacing next to the
    /// new one; only when there's a replacement fact to point at.
    @discardableResult
    public static func invalidate(_ db: Database, src: String, rel: String, dst: String? = nil,
                                  byFactId: String?, exceptEdgeId: String? = nil,
                                  supersededBy: String? = nil, now: Date = .now) throws -> Int {
        var query = EdgeRow
            .filter(Column("src_id") == src && Column("rel") == rel)
            .filter(Column("invalidated_at") == nil)
        if let dst { query = query.filter(Column("dst_id") == dst) }

        var n = 0
        var supersededSources = Set<String>()
        for var edge in try query.fetchAll(db) where edge.id != exceptEdgeId {
            edge.invalidatedAt = now
            edge.validTo = now
            edge.invalidatedByFactId = byFactId
            edge.supersededBy = supersededBy
            try edge.update(db)
            n += 1
            if let source = edge.sourceFactId, source != byFactId {
                supersededSources.insert(source)
            }
        }
        if let byFactId, !supersededSources.isEmpty {
            for sid in supersededSources {
                try db.execute(sql: "UPDATE fact SET superseded_by = ? WHERE id = ? AND superseded_by IS NULL",
                               arguments: [byFactId, sid])
            }
        }
        return n
    }
}
