import Foundation
import GRDB
import JKnowledge
import JStore

/// One-time fresh-start bootstrap after the v12 migration: registers the
/// built-in worlds and re-materializes stored history (conversations, meetings)
/// as pending episodes so the NEW pipeline re-extracts everything. Idempotent
/// twice over: a settings flag skips the scan, and episode external_ids make
/// re-runs merge instead of duplicate.
enum KnowledgeBootstrap {
    static func runIfNeeded(database: JarvisDatabase, store: KnowledgeStore, settings: SettingsStore) async {
        await store.ensureWorld(id: "chat", kind: "llm_text", displayName: "Conversations", enabled: true)
        await store.ensureWorld(id: "meetings", kind: "llm_text", displayName: "Meetings", enabled: true)
        await store.ensureWorld(id: "screen", kind: "llm_text", displayName: "Screen", enabled: true)

        let done = ((try? await settings.get("knowledge_bootstrap_v1", as: Bool.self)) ?? nil) ?? false
        guard !done else { return }

        do {
            try await backfillConversations(database: database, store: store)
            try await backfillMeetings(database: database, store: store)
            try? await settings.set("knowledge_bootstrap_v1", to: true)
        } catch {
            // A write failed mid-backfill: leave the flag unset so the next
            // boot retries; episode external_ids make the re-run idempotent.
        }
    }

    /// Every segment's user prose → one pending episode (external_id keyed by
    /// segment). The source messages are marked extracted so the turn-driven
    /// path never re-processes them.
    private static func backfillConversations(database: JarvisDatabase, store: KnowledgeStore) async throws {
        struct SegmentText { let id: String, startedAt: Date, text: String, messageIDs: [String] }
        let segments: [SegmentText] = (try? await database.reader.read { db -> [SegmentText] in
            let rows = try Row.fetchAll(db, sql: """
                SELECT m.id AS id, m.segment_id AS segment_id, m.content_json AS content_json,
                       s.started_at AS started_at
                FROM message m JOIN segment s ON s.id = m.segment_id
                WHERE m.role = 'user' AND m.active = 1
                ORDER BY m.segment_id, m.created_at
                """)
            var bySegment: [String: (startedAt: Date, texts: [String], ids: [String])] = [:]
            for row in rows {
                let text = plainText(row["content_json"] as String)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let segmentID: String = row["segment_id"]
                var entry = bySegment[segmentID] ?? (row["started_at"], [], [])
                if !text.isEmpty { entry.texts.append(text) }
                entry.ids.append(row["id"])
                bySegment[segmentID] = entry
            }
            return bySegment.compactMap { id, entry in
                guard !entry.texts.isEmpty else { return nil }
                return SegmentText(id: id, startedAt: entry.startedAt,
                                   text: entry.texts.joined(separator: "\n"), messageIDs: entry.ids)
            }
        }) ?? []

        for segment in segments {
            try await store.addEpisode(worldId: "chat", externalId: "segment:\(segment.id)",
                                       occurredAt: segment.startedAt,
                                       content: String(segment.text.prefix(12000)))
        }
        // Retire ALL user rows (including empty tool-result rows) in one pass.
        _ = try? await database.writer.write { db in
            try db.execute(sql: "UPDATE message SET extracted_at = ? WHERE role = 'user' AND extracted_at IS NULL",
                           arguments: [Date.now])
        }
    }

    /// Every meeting's transcript + overview → one pending episode.
    private static func backfillMeetings(database: JarvisDatabase, store: KnowledgeStore) async throws {
        struct MeetingText { let id: String, startedAt: Date, title: String?, text: String }
        let meetings: [MeetingText] = (try? await database.reader.read { db -> [MeetingText] in
            let rows = try Row.fetchAll(db, sql: """
                SELECT m.id AS id, m.started_at AS started_at, m.title AS title, m.overview AS overview,
                       (SELECT GROUP_CONCAT(text, char(10)) FROM meeting_segment ms
                        WHERE ms.meeting_id = m.id) AS transcript
                FROM meeting m
                """)
            return rows.compactMap { row in
                let overview: String? = row["overview"]
                let transcript: String? = row["transcript"]
                let text = [overview, transcript].compactMap(\.self).joined(separator: "\n")
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return MeetingText(id: row["id"], startedAt: row["started_at"], title: row["title"], text: text)
            }
        }) ?? []

        for meeting in meetings {
            try await store.addEpisode(worldId: "meetings", externalId: "meeting:\(meeting.id)",
                                       occurredAt: meeting.startedAt, title: meeting.title,
                                       content: String(meeting.text.prefix(12000)))
        }
    }
}
