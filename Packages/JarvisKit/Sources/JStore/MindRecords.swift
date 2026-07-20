import Foundation
import GRDB

// GRDB rows for the v13 decision engine: decision / delivery_state / facet /
// facet_evidence. See JarvisDatabase v13_mind.

public struct DecisionRow: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "decision"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var id: String
    public var ts: Date
    public var kind: String // trigger | heartbeat | delivery | reflection
    public var source: String
    public var triggerKey: String?
    public var action: String
    public var reason: String
    public var payloadJson: String
    public var latencyMs: Int?

    public init(id: String = UUID().uuidString, ts: Date = .now, kind: String, source: String,
                triggerKey: String? = nil, action: String, reason: String,
                payloadJson: String = "{}", latencyMs: Int? = nil) {
        self.id = id
        self.ts = ts
        self.kind = kind
        self.source = source
        self.triggerKey = triggerKey
        self.action = action
        self.reason = reason
        self.payloadJson = payloadJson
        self.latencyMs = latencyMs
    }
}

public struct DeliveryStateRow: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "delivery_state"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var dedupeKey: String
    public var category: String
    public var stage: String
    public var sentAt: Date

    public init(dedupeKey: String, category: String, stage: String, sentAt: Date = .now) {
        self.dedupeKey = dedupeKey
        self.category = category
        self.stage = stage
        self.sentAt = sentAt
    }
}

public struct FacetRow: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "facet"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var id: String { key }
    public var key: String
    public var `class`: String
    public var value: String
    public var state: String // active | provisional | candidate
    public var stability: Double
    public var evidenceCount: Int
    public var firstSeenAt: Date
    public var lastSeenAt: Date
    public var userState: String // auto | pinned | forgotten

    enum CodingKeys: String, CodingKey {
        case key, `class` = "class", value, state, stability, evidenceCount, firstSeenAt, lastSeenAt, userState
    }

    public init(key: String, class klass: String, value: String, state: String,
                stability: Double, evidenceCount: Int, firstSeenAt: Date, lastSeenAt: Date,
                userState: String = "auto") {
        self.key = key
        self.class = klass
        self.value = value
        self.state = state
        self.stability = stability
        self.evidenceCount = evidenceCount
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.userState = userState
    }
}

public struct FacetEvidenceRow: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "facet_evidence"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var id: String
    public var `class`: String
    public var key: String
    public var value: String
    public var cue: String // explicit | structural | behavioral | recurrence
    public var evidenceRef: String
    public var observedAt: Date
    public var consumedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, `class` = "class", key, value, cue, evidenceRef, observedAt, consumedAt
    }

    public init(id: String = UUID().uuidString, class klass: String, key: String, value: String,
                cue: String, evidenceRef: String, observedAt: Date = .now, consumedAt: Date? = nil) {
        self.id = id
        self.class = klass
        self.key = key
        self.value = value
        self.cue = cue
        self.evidenceRef = evidenceRef
        self.observedAt = observedAt
        self.consumedAt = consumedAt
    }
}
