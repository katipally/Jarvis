import Foundation
import GRDB
import JAgent
import JStore

/// Owns the rolling conversation: one continuous session that auto-splits into
/// segments on an idle gap. Memory extraction (M4) hooks the segment-close event.
actor SessionManager {
    private let database: JarvisDatabase
    /// Idle gap after which the next message starts a new conversation.
    /// Any send resets the clock; user-configurable in Settings.
    private var idleGap: TimeInterval

    private var sessionID: String?
    private var segmentID: String?
    private var lastActivity: Date = .distantPast

    /// Called with a segment id when it closes (idle split / shutdown) so memory
    /// extraction can run.
    private var onSegmentClose: (@Sendable (String) -> Void)?

    init(database: JarvisDatabase, idleGap: TimeInterval = 5 * 60) {
        self.database = database
        self.idleGap = idleGap
    }

    func setIdleGap(_ seconds: TimeInterval) {
        idleGap = max(60, seconds)
    }

    func setOnSegmentClose(_ handler: @escaping @Sendable (String) -> Void) {
        onSegmentClose = handler
    }

    func setExtractionStatus(_ segmentID: String, _ status: String) async {
        _ = try? await database.writer.write { db in
            if var segment = try Segment.fetchOne(db, key: segmentID) {
                segment.extractionStatus = status
                try segment.update(db)
            }
        }
    }

    struct TurnContext: Sendable {
        let segmentID: String
        /// True when this turn opened a fresh segment (the previous conversation
        /// closed) — the caller should reset its in-memory transcript.
        let startedNewSegment: Bool
    }

    /// Returns the segment a new user turn belongs to, splitting if we've been idle.
    func beginUserTurn(now: Date = .now) async throws -> TurnContext {
        if let segmentID, now.timeIntervalSince(lastActivity) <= idleGap {
            lastActivity = now
            return TurnContext(segmentID: segmentID, startedNewSegment: false)
        }
        if let segmentID {
            try await closeSegment(segmentID, reason: .idle, at: lastActivity)
        }
        let newSegment = try await openSegment(now: now)
        segmentID = newSegment
        lastActivity = now
        return TurnContext(segmentID: newSegment, startedNewSegment: true)
    }

    /// Close any segments a previous process left open (crash / quit) and re-fire
    /// extraction for closed segments whose extraction never ran. Call once at
    /// launch, after wiring `onSegmentClose`.
    func recoverOrphanedSegments(now: Date = .now) async {
        let pendingIDs: [String] = (try? await database.writer.write { db in
            let open = try Segment.filter(Column("ended_at") == nil).fetchAll(db)
            for var segment in open {
                segment.endedAt = now
                segment.closeReason = Segment.CloseReason.shutdown.rawValue
                try segment.update(db)
            }
            let stalled = try Segment
                .filter(Column("ended_at") != nil)
                .filter(["pending", "running"].contains(Column("extraction_status")))
                .fetchAll(db)
            return (open + stalled).map(\.id)
        }) ?? []
        for id in Set(pendingIDs) {
            onSegmentClose?(id)
        }
    }

    /// Best-effort close of the live segment on app termination.
    func closeCurrentSegment(now: Date = .now) async {
        guard let segmentID else { return }
        try? await closeSegment(segmentID, reason: .shutdown, at: now)
        self.segmentID = nil
    }

    /// User-facing rename in the History tab. An empty title restores the
    /// first-message preview.
    func rename(segmentID: String, title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try? await database.writer.write { db in
            try db.execute(
                sql: "UPDATE segment SET title = ? WHERE id = ?",
                arguments: [trimmed.isEmpty ? nil : trimmed, segmentID]
            )
        }
    }

    /// User-facing delete in the History tab: removes the conversation and its
    /// messages. Deleting the live conversation starts a fresh one on next send.
    func deleteSegment(_ id: String) async {
        _ = try? await database.writer.write { db in
            try db.execute(sql: "DELETE FROM message WHERE segment_id = ?", arguments: [id])
            try Segment.deleteOne(db, key: id)
        }
        if segmentID == id {
            segmentID = nil
            lastActivity = .distantPast
        }
    }

    private func openSegment(now: Date) async throws -> String {
        let sid: String
        if let sessionID {
            sid = sessionID
        } else {
            let session = Session(createdAt: now)
            try await database.writer.write { db in try session.insert(db) }
            sessionID = session.id
            sid = session.id
        }
        let segment = Segment(sessionId: sid, startedAt: now)
        try await database.writer.write { db in try segment.insert(db) }
        return segment.id
    }

    private func closeSegment(_ id: String, reason: Segment.CloseReason, at: Date) async throws {
        try await database.writer.write { db in
            if var segment = try Segment.fetchOne(db, key: id) {
                segment.endedAt = at
                segment.closeReason = reason.rawValue
                try segment.update(db)
            }
        }
        onSegmentClose?(id)
    }

    @discardableResult
    func append(role: MessageRole, content: [ContentBlock], status: MessageRecord.Status,
                runId: String? = nil, model: String? = nil, provider: String? = nil,
                usage: Usage? = nil, kind: MessageRecord.Kind = .chat, now: Date = .now) async throws -> String {
        guard let segmentID else { throw ProviderError.notConfigured("no active segment") }
        let json = encodeContent(content)
        let id = UUID().uuidString
        try await database.writer.write { db in
            let maxSeq = try Int.fetchOne(db, sql:
                "SELECT COALESCE(MAX(seq), -1) FROM message WHERE segment_id = ?", arguments: [segmentID]) ?? -1
            let record = MessageRecord(
                id: id, segmentId: segmentID, seq: maxSeq + 1,
                role: MessageRecord.Role(rawValue: role.rawValue) ?? .assistant,
                status: status, contentJson: json,
                runId: runId, model: model, provider: provider,
                inputTokens: usage?.inputTokens, outputTokens: usage?.outputTokens, createdAt: now,
                kind: kind
            )
            try record.insert(db)
        }
        lastActivity = now
        return id
    }

    func updateStatus(messageID: String, status: MessageRecord.Status, content: [ContentBlock]? = nil) async {
        _ = try? await database.writer.write { db in
            guard var record = try MessageRecord.fetchOne(db, key: messageID) else { return }
            record.status = status.rawValue
            if let content { record.contentJson = encodeContentStatic(content) }
            try record.update(db)
        }
    }

    // MARK: - History

    struct SegmentSummary: Sendable, Identifiable {
        let id: String
        let startedAt: Date
        let title: String?
        let preview: String
        let messageCount: Int
    }

    func recentSegments(limit: Int = 40) async -> [SegmentSummary] {
        (try? await database.reader.read { db -> [SegmentSummary] in
            let segments = try Segment.order(Column("started_at").desc).limit(limit).fetchAll(db)
            return try segments.map { seg in
                let msgs = try MessageRecord
                    .filter(Column("segment_id") == seg.id)
                    .order(Column("seq"))
                    .fetchAll(db)
                let firstUser = msgs.first { $0.role == MessageRole.user.rawValue }
                let preview = firstUser.map { Self.previewText($0.contentJson) } ?? ""
                return SegmentSummary(
                    id: seg.id, startedAt: seg.startedAt, title: seg.title,
                    preview: preview, messageCount: msgs.count
                )
            }
        }) ?? []
    }

    struct StoredMessage: Sendable, Identifiable {
        let id: String
        let role: MessageRole
        let content: [ContentBlock]
        let status: MessageRecord.Status
        let createdAt: Date
        let kind: String
    }

    func messages(inSegment id: String) async -> [StoredMessage] {
        (try? await database.reader.read { db -> [StoredMessage] in
            let records = try MessageRecord
                .filter(Column("segment_id") == id)
                .filter(Column("active") == true)
                .order(Column("seq"))
                .fetchAll(db)
            return records.map(Self.stored)
        }) ?? []
    }

    /// Older persisted conversation across ALL segments, newest-last — the
    /// scroll-up lazy-load source for the Home transcript (iMessage style).
    func messagesBefore(_ cutoff: Date, limit: Int = 30) async -> [StoredMessage] {
        (try? await database.reader.read { db -> [StoredMessage] in
            let records = try MessageRecord
                .filter(Column("created_at") < cutoff)
                .filter(Column("active") == true)
                .order(Column("created_at").desc)
                .limit(limit)
                .fetchAll(db)
            return records.reversed().map(Self.stored)
        }) ?? []
    }

    private static func stored(_ r: MessageRecord) -> StoredMessage {
        StoredMessage(
            id: r.id,
            role: MessageRole(rawValue: r.role) ?? .assistant,
            content: decodeContent(r.contentJson),
            status: MessageRecord.Status(rawValue: r.status) ?? .complete,
            createdAt: r.createdAt,
            kind: r.kind
        )
    }

    private static func previewText(_ json: String) -> String {
        decodeContent(json).compactMap { if case .text(let t) = $0 { return t } else { return nil } }
            .joined().prefix(80).description
    }
}

// Content (de)serialization — kept free-standing so both actor and helpers share it.
private let contentEncoder = JSONEncoder()
private let contentDecoder = JSONDecoder()

func encodeContent(_ content: [ContentBlock]) -> String {
    encodeContentStatic(content)
}

func encodeContentStatic(_ content: [ContentBlock]) -> String {
    guard let data = try? contentEncoder.encode(content) else { return "[]" }
    return String(decoding: data, as: UTF8.self)
}

func decodeContent(_ json: String) -> [ContentBlock] {
    guard let data = json.data(using: .utf8),
          let blocks = try? contentDecoder.decode([ContentBlock].self, from: data) else { return [] }
    return blocks
}
