import Foundation
import GRDB

public struct ApprovalRuleRow: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "approval_rule"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var id: String
    public var toolName: String
    public var scopeKey: String?
    public var decision: String // allow | deny
    public var createdAt: Date
    public var expiresAt: Date?

    public init(id: String = UUID().uuidString, toolName: String, scopeKey: String?,
                decision: String, createdAt: Date = .now, expiresAt: Date? = nil) {
        self.id = id
        self.toolName = toolName
        self.scopeKey = scopeKey
        self.decision = decision
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

public struct ApprovalEventRow: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "approval_event"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var id: String
    public var runId: String?
    public var toolCallId: String?
    public var toolName: String
    public var summary: String?
    public var allowed: Bool
    public var decidedBy: String
    public var createdAt: Date

    public init(id: String = UUID().uuidString, runId: String?, toolCallId: String?,
                toolName: String, summary: String?, allowed: Bool, decidedBy: String, createdAt: Date = .now) {
        self.id = id
        self.runId = runId
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.summary = summary
        self.allowed = allowed
        self.decidedBy = decidedBy
        self.createdAt = createdAt
    }
}

public struct ArtifactRow: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "artifact"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var id: String
    public var kind: String
    public var runId: String?
    public var messageId: String?
    public var path: String
    public var filename: String?
    public var mime: String?
    public var bytes: Int?
    public var preview: String?
    public var createdAt: Date

    public init(id: String = UUID().uuidString, kind: String, runId: String? = nil, messageId: String? = nil,
                path: String, filename: String? = nil, mime: String? = nil, bytes: Int? = nil,
                preview: String? = nil, createdAt: Date = .now) {
        self.id = id
        self.kind = kind
        self.runId = runId
        self.messageId = messageId
        self.path = path
        self.filename = filename
        self.mime = mime
        self.bytes = bytes
        self.preview = preview
        self.createdAt = createdAt
    }
}

public struct RunRow: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "run"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var id: String
    public var kind: String // foreground | background | cron | nudge
    public var segmentId: String?
    public var initiator: String?
    public var status: String
    public var startedAt: Date
    public var endedAt: Date?
    public var error: String?
    public var totalInputTokens: Int
    public var totalOutputTokens: Int

    public init(id: String = UUID().uuidString, kind: String, segmentId: String? = nil, initiator: String? = nil,
                status: String, startedAt: Date = .now, endedAt: Date? = nil, error: String? = nil,
                totalInputTokens: Int = 0, totalOutputTokens: Int = 0) {
        self.id = id
        self.kind = kind
        self.segmentId = segmentId
        self.initiator = initiator
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.error = error
        self.totalInputTokens = totalInputTokens
        self.totalOutputTokens = totalOutputTokens
    }
}

public struct ToolCallRow: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "tool_call"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var id: String
    public var runId: String
    public var messageId: String?
    public var name: String
    public var inputJson: String
    public var state: String
    public var outputPreview: String?
    public var outputArtifactId: String?
    public var durationMs: Int?
    public var createdAt: Date

    public init(id: String = UUID().uuidString, runId: String, messageId: String? = nil, name: String,
                inputJson: String, state: String, outputPreview: String? = nil, outputArtifactId: String? = nil,
                durationMs: Int? = nil, createdAt: Date = .now) {
        self.id = id
        self.runId = runId
        self.messageId = messageId
        self.name = name
        self.inputJson = inputJson
        self.state = state
        self.outputPreview = outputPreview
        self.outputArtifactId = outputArtifactId
        self.durationMs = durationMs
        self.createdAt = createdAt
    }
}
