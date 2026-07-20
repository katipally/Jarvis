import Foundation

/// Closed entity taxonomy. The extractor emits free text; anything unknown
/// collapses to `.thing` so the graph never grows ad-hoc kinds again.
public enum EntityType: String, Sendable, Codable, CaseIterable {
    case person, org, place, event, topic, project, thing

    public static func from(_ raw: String) -> EntityType {
        EntityType(rawValue: raw.trimmingCharacters(in: .whitespaces).lowercased()) ?? .thing
    }
}

public struct ExtractedFact: Sendable {
    public var text: String
    public var salience: Double

    public init(text: String, salience: Double = 0.5) {
        self.text = text
        self.salience = salience
    }
}

public struct ExtractedEntity: Sendable {
    public var name: String
    public var type: EntityType

    public init(name: String, type: EntityType) {
        self.name = name
        self.type = type
    }
}

public struct ExtractedRelation: Sendable {
    public var subject: String
    public var relation: String
    public var object: String

    public init(subject: String, relation: String, object: String) {
        self.subject = subject
        self.relation = relation
        self.object = object
    }
}

/// One extraction over an episode. `invalidations` are relations that stopped
/// being true (quit a job, moved away); object may be empty = any target.
public struct KnowledgeExtractionResult: Sendable {
    public var facts: [ExtractedFact]
    public var entities: [ExtractedEntity]
    public var relations: [ExtractedRelation]
    public var invalidations: [ExtractedRelation]

    public init(facts: [ExtractedFact] = [], entities: [ExtractedEntity] = [],
                relations: [ExtractedRelation] = [], invalidations: [ExtractedRelation] = []) {
        self.facts = facts
        self.entities = entities
        self.relations = relations
        self.invalidations = invalidations
    }
}

public struct RetrievedFact: Sendable, Identifiable {
    public var id: String
    public var text: String
    public var score: Double
}

/// What one ingest wrote — feeds ingest_run bookkeeping and the Activity feed.
public struct IngestCounts: Sendable {
    public var facts = 0
    public var entities = 0
    public var edges = 0

    public init() {}
}

/// Names the extractor uses for the user; all resolve to the single is_self
/// "Me" person node instead of spawning "User"/"I" ghost entities.
public let selfAliases: Set<String> = ["me", "i", "user", "the user", "myself"]

/// Query tokenization shared by lexical search and graph seeding.
public func queryTokens(_ s: String) -> [String] {
    s.lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { $0.count > 1 }
}
