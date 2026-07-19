import Foundation
import GRDB

public struct CronJobRow: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "cron_job"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var id: String
    public var name: String
    public var cronExpr: String
    public var prompt: String
    public var enabled: Bool
    public var lastRunAt: Date?
    public var nextRunAt: Date
    public var lastStatus: String?
    public var createdAt: Date

    public init(id: String = UUID().uuidString, name: String, cronExpr: String, prompt: String,
                enabled: Bool = true, lastRunAt: Date? = nil, nextRunAt: Date, lastStatus: String? = nil, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.cronExpr = cronExpr
        self.prompt = prompt
        self.enabled = enabled
        self.lastRunAt = lastRunAt
        self.nextRunAt = nextRunAt
        self.lastStatus = lastStatus
        self.createdAt = createdAt
    }
}

public struct NudgeRow: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "nudge"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var id: String
    public var createdAt: Date
    public var trigger: String
    public var frameId: String?
    public var dedupKey: String?
    public var title: String?
    public var body: String
    public var state: String

    public init(id: String = UUID().uuidString, createdAt: Date = .now, trigger: String, frameId: String? = nil,
                dedupKey: String? = nil, title: String? = nil, body: String, state: String = "shown") {
        self.id = id
        self.createdAt = createdAt
        self.trigger = trigger
        self.frameId = frameId
        self.dedupKey = dedupKey
        self.title = title
        self.body = body
        self.state = state
    }
}
