import Foundation
import GRDB

public struct MemoryRow: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "memory"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var id: String
    public var tier: String
    public var kind: String
    public var text: String
    public var importance: Double
    public var sourceSegmentId: String?
    public var status: String
    public var supersededBy: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var lastAccessedAt: Date?
    public var accessCount: Int

    public init(id: String = UUID().uuidString, tier: String, kind: String, text: String,
                importance: Double = 0.5, sourceSegmentId: String? = nil, status: String = "active",
                supersededBy: String? = nil, createdAt: Date = .now, updatedAt: Date = .now,
                lastAccessedAt: Date? = nil, accessCount: Int = 0) {
        self.id = id
        self.tier = tier
        self.kind = kind
        self.text = text
        self.importance = importance
        self.sourceSegmentId = sourceSegmentId
        self.status = status
        self.supersededBy = supersededBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastAccessedAt = lastAccessedAt
        self.accessCount = accessCount
    }
}

public struct EmbeddingRow: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "embedding"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var ownerKind: String
    public var ownerId: String
    public var modelId: String
    public var dim: Int
    public var vector: Data

    public init(ownerKind: String, ownerId: String, modelId: String, dim: Int, vector: Data) {
        self.ownerKind = ownerKind
        self.ownerId = ownerId
        self.modelId = modelId
        self.dim = dim
        self.vector = vector
    }
}

public struct GraphNodeRow: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "graph_node"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var id: String
    public var kind: String
    public var name: String
    public var nameNorm: String
    public var attrsJson: String?
    public var validFrom: Date
    public var validTo: Date?
    public var supersededBy: String?
    public var createdAt: Date

    public init(id: String = UUID().uuidString, kind: String, name: String, nameNorm: String,
                attrsJson: String? = nil, validFrom: Date = .now, validTo: Date? = nil,
                supersededBy: String? = nil, createdAt: Date = .now) {
        self.id = id
        self.kind = kind
        self.name = name
        self.nameNorm = nameNorm
        self.attrsJson = attrsJson
        self.validFrom = validFrom
        self.validTo = validTo
        self.supersededBy = supersededBy
        self.createdAt = createdAt
    }
}

public struct GraphEdgeRow: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "graph_edge"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var id: String
    public var srcId: String
    public var dstId: String
    public var relation: String
    public var attrsJson: String?
    public var weight: Double
    public var sourceMemoryId: String?
    public var validFrom: Date
    public var validTo: Date?
    public var supersededBy: String?
    public var createdAt: Date

    public init(id: String = UUID().uuidString, srcId: String, dstId: String, relation: String,
                attrsJson: String? = nil, weight: Double = 1.0, sourceMemoryId: String? = nil,
                validFrom: Date = .now, validTo: Date? = nil, supersededBy: String? = nil, createdAt: Date = .now) {
        self.id = id
        self.srcId = srcId
        self.dstId = dstId
        self.relation = relation
        self.attrsJson = attrsJson
        self.weight = weight
        self.sourceMemoryId = sourceMemoryId
        self.validFrom = validFrom
        self.validTo = validTo
        self.supersededBy = supersededBy
        self.createdAt = createdAt
    }
}

public struct NodeAliasRow: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "node_alias"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var nodeId: String
    public var alias: String
    public var aliasNorm: String

    public init(nodeId: String, alias: String, aliasNorm: String) {
        self.nodeId = nodeId
        self.alias = alias
        self.aliasNorm = aliasNorm
    }
}
