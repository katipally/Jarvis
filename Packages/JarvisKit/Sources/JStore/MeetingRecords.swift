import Foundation
import GRDB

/// A captured meeting: one row per session, finalized with an LLM summary.
public struct MeetingRow: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "meeting"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public enum SummaryStatus: String, Codable, Sendable { case pending, done, skipped }

    public var id: String
    public var startedAt: Date
    public var endedAt: Date?
    public var appBundleId: String?
    public var title: String?
    public var overview: String?
    public var summaryStatus: String
    public var createdAt: Date

    public init(id: String = UUID().uuidString, startedAt: Date = .now, endedAt: Date? = nil,
                appBundleId: String? = nil, title: String? = nil, overview: String? = nil,
                summaryStatus: SummaryStatus = .pending, createdAt: Date = .now) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.appBundleId = appBundleId
        self.title = title
        self.overview = overview
        self.summaryStatus = summaryStatus.rawValue
        self.createdAt = createdAt
    }
}

/// One attributed utterance in a meeting. `source` is "mic" (you) or "system" (them).
public struct MeetingSegmentRow: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "meeting_segment"
    public static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    public static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    public enum Source: String, Codable, Sendable { case mic, system }

    public var id: String
    public var meetingId: String
    public var ts: Date
    public var source: String
    public var text: String

    public init(id: String = UUID().uuidString, meetingId: String, ts: Date = .now, source: Source, text: String) {
        self.id = id
        self.meetingId = meetingId
        self.ts = ts
        self.source = source.rawValue
        self.text = text
    }
}
