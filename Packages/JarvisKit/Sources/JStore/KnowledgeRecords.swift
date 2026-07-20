import Foundation
import GRDB

// GRDB rows for the v12 knowledge core: world / episode / fact / entity /
// entity_alias / edge / ingest_run. See JarvisDatabase v12_knowledge_core.

public struct WorldRow: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "world"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var id: String
    public var kind: String // llm_text | structured
    public var displayName: String
    public var enabled: Bool
    public var cursorJson: String?
    public var lastSyncAt: Date?
    public var lastStatus: String?
    public var lastError: String?
    public var createdAt: Date

    public init(id: String, kind: String, displayName: String, enabled: Bool = false,
                cursorJson: String? = nil, lastSyncAt: Date? = nil, lastStatus: String? = nil,
                lastError: String? = nil, createdAt: Date = .now) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.enabled = enabled
        self.cursorJson = cursorJson
        self.lastSyncAt = lastSyncAt
        self.lastStatus = lastStatus
        self.lastError = lastError
        self.createdAt = createdAt
    }
}

public struct EpisodeRow: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "episode"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var id: String
    public var worldId: String
    public var externalId: String?
    public var occurredAt: Date
    public var title: String?
    public var content: String
    public var extractionStatus: String // pending | done | skipped | failed
    public var extractedAt: Date?
    public var createdAt: Date

    public init(id: String = UUID().uuidString, worldId: String, externalId: String? = nil,
                occurredAt: Date, title: String? = nil, content: String,
                extractionStatus: String = "pending", extractedAt: Date? = nil, createdAt: Date = .now) {
        self.id = id
        self.worldId = worldId
        self.externalId = externalId
        self.occurredAt = occurredAt
        self.title = title
        self.content = content
        self.extractionStatus = extractionStatus
        self.extractedAt = extractedAt
        self.createdAt = createdAt
    }
}

public struct FactRow: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "fact"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var id: String
    public var episodeId: String?
    public var text: String
    public var kind: String // raw | abstract
    public var salience: Double
    public var supersededBy: String?
    public var createdAt: Date

    public init(id: String = UUID().uuidString, episodeId: String? = nil, text: String,
                kind: String = "raw", salience: Double = 0.5, supersededBy: String? = nil,
                createdAt: Date = .now) {
        self.id = id
        self.episodeId = episodeId
        self.text = text
        self.kind = kind
        self.salience = salience
        self.supersededBy = supersededBy
        self.createdAt = createdAt
    }
}

public struct EntityRow: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "entity"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var id: String
    public var type: String // person | org | place | event | topic | project | thing
    public var name: String
    public var norm: String
    public var attrsJson: String
    public var isSelf: Bool
    public var createdAt: Date

    public init(id: String, type: String, name: String, norm: String,
                attrsJson: String = "{}", isSelf: Bool = false, createdAt: Date = .now) {
        self.id = id
        self.type = type
        self.name = name
        self.norm = norm
        self.attrsJson = attrsJson
        self.isSelf = isSelf
        self.createdAt = createdAt
    }
}

public struct EntityAliasRow: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "entity_alias"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var entityId: String
    public var alias: String
    public var aliasNorm: String

    public init(entityId: String, alias: String, aliasNorm: String) {
        self.entityId = entityId
        self.alias = alias
        self.aliasNorm = aliasNorm
    }
}

public struct EdgeRow: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "edge"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var id: String
    public var srcId: String
    public var dstId: String
    public var rel: String
    public var confidence: Double
    public var validFrom: Date?
    public var validTo: Date?
    public var createdAt: Date
    public var invalidatedAt: Date?
    public var invalidatedByFactId: String?
    public var supersededBy: String?
    public var sourceFactId: String?
    public var sourceEpisodeId: String?
    public var worldId: String?

    public init(id: String = UUID().uuidString, srcId: String, dstId: String, rel: String,
                confidence: Double = 0.8, validFrom: Date? = nil, validTo: Date? = nil,
                createdAt: Date = .now, invalidatedAt: Date? = nil, invalidatedByFactId: String? = nil,
                supersededBy: String? = nil, sourceFactId: String? = nil,
                sourceEpisodeId: String? = nil, worldId: String? = nil) {
        self.id = id
        self.srcId = srcId
        self.dstId = dstId
        self.rel = rel
        self.confidence = confidence
        self.validFrom = validFrom
        self.validTo = validTo
        self.createdAt = createdAt
        self.invalidatedAt = invalidatedAt
        self.invalidatedByFactId = invalidatedByFactId
        self.supersededBy = supersededBy
        self.sourceFactId = sourceFactId
        self.sourceEpisodeId = sourceEpisodeId
        self.worldId = worldId
    }
}

public struct IngestRunRow: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "ingest_run"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var id: String
    public var worldId: String
    public var startedAt: Date
    public var endedAt: Date?
    public var status: String // running | done | empty | error
    public var episodesAdded: Int
    public var factsAdded: Int
    public var entitiesAdded: Int
    public var edgesAdded: Int
    public var error: String?

    public init(id: String = UUID().uuidString, worldId: String, startedAt: Date = .now,
                endedAt: Date? = nil, status: String = "running", episodesAdded: Int = 0,
                factsAdded: Int = 0, entitiesAdded: Int = 0, edgesAdded: Int = 0, error: String? = nil) {
        self.id = id
        self.worldId = worldId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.episodesAdded = episodesAdded
        self.factsAdded = factsAdded
        self.entitiesAdded = entitiesAdded
        self.edgesAdded = edgesAdded
        self.error = error
    }
}
