import Foundation
import GRDB

public struct Session: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "session"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var id: String
    public var createdAt: Date
    public var archivedAt: Date?

    public init(id: String = UUID().uuidString, createdAt: Date = .now, archivedAt: Date? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.archivedAt = archivedAt
    }
}

public struct Segment: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "segment"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public enum CloseReason: String, Codable, Sendable {
        case idle, topicShift = "topic_shift", manual, shutdown
    }

    public var id: String
    public var sessionId: String
    public var startedAt: Date
    public var endedAt: Date?
    public var title: String?
    public var summary: String?
    public var closeReason: String?
    public var extractionStatus: String

    public init(
        id: String = UUID().uuidString,
        sessionId: String,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        title: String? = nil,
        summary: String? = nil,
        closeReason: CloseReason? = nil,
        extractionStatus: String = "pending"
    ) {
        self.id = id
        self.sessionId = sessionId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.title = title
        self.summary = summary
        self.closeReason = closeReason?.rawValue
        self.extractionStatus = extractionStatus
    }
}

public struct MessageRecord: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "message"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public enum Role: String, Codable, Sendable { case user, assistant, system, tool }
    public enum Status: String, Codable, Sendable { case streaming, complete, aborted, error }

    public var id: String
    public var segmentId: String
    public var seq: Int
    public var role: String
    public var status: String
    public var contentJson: String
    public var runId: String?
    public var model: String?
    public var provider: String?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        segmentId: String,
        seq: Int,
        role: Role,
        status: Status,
        contentJson: String,
        runId: String? = nil,
        model: String? = nil,
        provider: String? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.segmentId = segmentId
        self.seq = seq
        self.role = role.rawValue
        self.status = status.rawValue
        self.contentJson = contentJson
        self.runId = runId
        self.model = model
        self.provider = provider
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.createdAt = createdAt
    }
}

public struct Setting: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "setting"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public var key: String
    public var valueJson: String

    public init(key: String, valueJson: String) {
        self.key = key
        self.valueJson = valueJson
    }
}

public struct ProviderAccount: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "provider_account"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public enum Provider: String, Codable, Sendable { case anthropic, openai, minimax, custom }

    public var id: String
    public var provider: String
    public var baseUrl: String?
    public var label: String?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        provider: Provider,
        baseUrl: String? = nil,
        label: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.provider = provider.rawValue
        self.baseUrl = baseUrl
        self.label = label
        self.createdAt = createdAt
    }
}

/// Typed access to the `setting` key/value table.
public struct SettingsStore: Sendable {
    private let db: JarvisDatabase

    public init(db: JarvisDatabase) { self.db = db }

    public func get<T: Codable & Sendable>(_ key: String, as type: T.Type) async throws -> T? {
        let json = try await db.reader.read { db in
            try Setting.fetchOne(db, key: key)?.valueJson
        }
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    public func set<T: Codable & Sendable>(_ key: String, to value: T) async throws {
        let data = try JSONEncoder().encode(value)
        let json = String(decoding: data, as: UTF8.self)
        try await db.writer.write { db in
            try Setting(key: key, valueJson: json).save(db)
        }
    }
}
