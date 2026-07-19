import Foundation
import GRDB

/// A future follow-up the user committed to ("send the deck by 3pm"), mined
/// from conversation. Fired as a proactive interrupt as its due time nears.
public struct CommitmentRow: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "commitment"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public enum Status: String, Codable, Sendable { case open, notified, done, dismissed }

    public var id: String
    public var text: String
    public var dueAt: Date?
    public var dedupeKey: String?
    public var sourceSegmentId: String?
    public var status: String
    public var createdAt: Date

    public init(id: String = UUID().uuidString, text: String, dueAt: Date? = nil, dedupeKey: String? = nil,
                sourceSegmentId: String? = nil, status: Status = .open, createdAt: Date = .now) {
        self.id = id
        self.text = text
        self.dueAt = dueAt
        self.dedupeKey = dedupeKey
        self.sourceSegmentId = sourceSegmentId
        self.status = status.rawValue
        self.createdAt = createdAt
    }
}

/// An action item extracted from chat or a meeting. Lands as `suggested` for
/// user review (omi staged-tasks pattern), promoted to `open`, then `done`.
public struct TaskRow: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "task"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public enum Source: String, Codable, Sendable { case chat, meeting, manual }
    public enum Status: String, Codable, Sendable { case suggested, open, done, dismissed }

    public var id: String
    public var text: String
    public var source: String
    public var sourceId: String?
    public var status: String
    public var dueAt: Date?
    public var createdAt: Date

    public init(id: String = UUID().uuidString, text: String, source: Source, sourceId: String? = nil,
                status: Status = .suggested, dueAt: Date? = nil, createdAt: Date = .now) {
        self.id = id
        self.text = text
        self.source = source.rawValue
        self.sourceId = sourceId
        self.status = status.rawValue
        self.dueAt = dueAt
        self.createdAt = createdAt
    }
}
