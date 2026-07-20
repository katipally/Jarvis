import Foundation
import GRDB

// GRDB rows for the decision engine: decision / delivery_state.
// See JarvisDatabase v13_mind.

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
