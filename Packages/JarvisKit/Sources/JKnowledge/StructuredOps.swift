import Foundation
import GRDB
import JStore

// Deterministic, no-LLM graph writes for structured sources (takt's graph-build
// model): calendar events and contacts map straight to entities/edges. Same
// input → same graph — deterministic entity ids + live-edge dedup make re-syncs
// idempotent upserts.

public struct EntityOp: Sendable {
    public var name: String
    public var type: EntityType
    public var aliases: [String]
    /// True = this name is another name for the user; becomes an alias of the
    /// single is_self node instead of a new entity.
    public var selfAlias: Bool

    public init(name: String, type: EntityType, aliases: [String] = [], selfAlias: Bool = false) {
        self.name = name
        self.type = type
        self.aliases = aliases
        self.selfAlias = selfAlias
    }
}

public struct EdgeOp: Sendable {
    public var subject: String
    public var subjectType: EntityType
    public var rel: String
    public var object: String
    public var objectType: EntityType
    public var validFrom: Date?
    public var validTo: Date?

    public init(subject: String, subjectType: EntityType, rel: String,
                object: String, objectType: EntityType,
                validFrom: Date? = nil, validTo: Date? = nil) {
        self.subject = subject
        self.subjectType = subjectType
        self.rel = rel
        self.object = object
        self.objectType = objectType
        self.validFrom = validFrom
        self.validTo = validTo
    }
}

public struct StructuredOps: Sendable {
    public var entities: [EntityOp] = []
    public var edges: [EdgeOp] = []

    public init() {}

    public var isEmpty: Bool { entities.isEmpty && edges.isEmpty }
}

public extension KnowledgeStore {
    /// Apply deterministic graph ops from a structured world. Structured facts
    /// come from the source of truth itself, so confidence is high and no
    /// validator/extraction runs.
    @discardableResult
    func applyStructured(_ ops: StructuredOps, worldId: String, now: Date = .now) async -> IngestCounts {
        guard !ops.isEmpty else { return IngestCounts() }
        let counts = (try? await database.writer.write { db -> IngestCounts in
            var counts = IngestCounts()

            func resolve(_ name: String, _ type: EntityType) throws -> String? {
                let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { return nil }
                guard let (id, created) = try GraphWriter.upsertEntity(db, name: clean, type: type, now: now)
                else { return nil }
                if created { counts.entities += 1 }
                return id
            }

            for op in ops.entities {
                let clean = op.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { continue }
                let id: String?
                if op.selfAlias {
                    id = try GraphWriter.selfEntity(db, now: now)
                } else {
                    id = try resolve(clean, op.type)
                }
                guard let id else { continue }
                for alias in [clean] + op.aliases {
                    let norm = EntityResolver.normName(alias)
                    guard !norm.isEmpty else { continue }
                    try EntityAliasRow(entityId: id, alias: alias, aliasNorm: norm).insert(db, onConflict: .ignore)
                }
            }

            for op in ops.edges {
                let rel = Relations.normalize(op.rel)
                guard !rel.isEmpty,
                      let src = try resolve(op.subject, op.subjectType),
                      let dst = try resolve(op.object, op.objectType),
                      src != dst else { continue }
                if try GraphWriter.upsertEdge(db, src: src, dst: dst, rel: rel, confidence: 0.95,
                                              worldId: worldId,
                                              validFrom: op.validFrom, validTo: op.validTo, now: now) {
                    counts.edges += 1
                }
            }
            return counts
        }) ?? IngestCounts()

        if counts.entities > 0 || counts.edges > 0 {
            Task { @MainActor in
                NotificationCenter.default.post(name: .jarvisGraphDidChange, object: nil)
            }
        }
        return counts
    }
}
