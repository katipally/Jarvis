import Foundation

public enum MemoryKind: String, Sendable, Codable, CaseIterable {
    case fact, preference, event, task, insight
}

public struct ExtractedMemory: Sendable, Codable {
    public var kind: MemoryKind
    public var text: String
    public var importance: Double

    public init(kind: MemoryKind, text: String, importance: Double = 0.5) {
        self.kind = kind
        self.text = text
        self.importance = importance
    }
}

public struct ExtractedEntity: Sendable, Codable {
    public var name: String
    public var kind: String // person | org | project | place | topic | artifact

    public init(name: String, kind: String) {
        self.name = name
        self.kind = kind
    }
}

public struct ExtractedRelation: Sendable, Codable {
    public var subject: String
    public var relation: String
    public var object: String

    public init(subject: String, relation: String, object: String) {
        self.subject = subject
        self.relation = relation
        self.object = object
    }
}

public struct ExtractionResult: Sendable, Codable {
    public var memories: [ExtractedMemory]
    public var entities: [ExtractedEntity]
    public var relations: [ExtractedRelation]

    public init(memories: [ExtractedMemory] = [], entities: [ExtractedEntity] = [], relations: [ExtractedRelation] = []) {
        self.memories = memories
        self.entities = entities
        self.relations = relations
    }
}

public struct RetrievedMemory: Sendable, Identifiable {
    public var id: String
    public var text: String
    public var kind: String
    public var score: Double
}

/// Relations that hold a single current value; a new one supersedes the old.
let functionalRelations: Set<String> = [
    "lives_in", "works_at", "located_in", "employed_by", "married_to",
    "reports_to", "owns", "based_in", "member_of", "uses",
]

func normalizeText(_ s: String) -> String {
    s.lowercased()
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}
