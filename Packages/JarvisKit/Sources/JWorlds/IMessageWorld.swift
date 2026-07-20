import Foundation
import GRDB
import JKnowledge

/// iMessage via ~/Library/Messages/chat.db (needs Full Disk Access). Cursor =
/// MAX(message.ROWID). New rows are grouped per chat → one episode per chat per
/// sync. Messages with NULL `text` carry a typedstream `attributedBody`; a
/// best-effort scanner recovers the string (known risk — partial coverage OK).
public struct IMessageWorld: WorldConnector {
    public let worldId = "imessage"
    let chatDB: URL
    let scratchDirectory: URL

    public init(chatDB: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Messages/chat.db"),
        scratchDirectory: URL) {
        self.chatDB = chatDB
        self.scratchDirectory = scratchDirectory
    }

    struct Cursor: Codable {
        var lastRowid: Int64 = 0
    }

    static let maxPerSync = 500

    struct RawMessage {
        let rowid: Int64
        let chat: String
        let sender: String?
        let isFromMe: Bool
        let date: Date
        let text: String
    }

    public func sync(cursorJson: String?) async throws -> WorldSyncResult {
        guard FileManager.default.isReadableFile(atPath: chatDB.path) else {
            throw WorldError.needsFullDiskAccess
        }
        let old = WorldCursor.decode(cursorJson, as: Cursor.self) ?? Cursor()
        // First enable: start from the current head, don't ingest years of history.
        let queue = try openReadOnly()
        if old.lastRowid == 0 {
            let head = try await queue.read { db in
                try Int64.fetchOne(db, sql: "SELECT MAX(ROWID) FROM message") ?? 0
            }
            return WorldSyncResult(cursorJson: WorldCursor.encode(Cursor(lastRowid: head)))
        }
        // The cursor advances over every SCANNED row, not just rows whose text
        // was recoverable — otherwise a window of textless rows (stickers,
        // attachments) wedges the connector on the same 500 rows forever.
        let (messages, scannedMax) = try await Self.fetch(queue, after: old.lastRowid)

        var result = WorldSyncResult()
        let newest = max(old.lastRowid, scannedMax)
        var byChat: [String: [RawMessage]] = [:]
        for message in messages {
            byChat[message.chat, default: []].append(message)
        }
        for (chat, rows) in byChat {
            let lines = rows.map { "[\($0.isFromMe ? "Me" : ($0.sender ?? "them"))]: \($0.text)" }
            let content = "iMessage conversation with \(chat):\n" + lines.joined(separator: "\n")
            result.episodes.append(EpisodeDraft(
                externalId: "chat:\(chat):\(rows.map(\.rowid).max() ?? 0)",
                occurredAt: rows.map(\.date).max() ?? .now,
                title: "Messages with \(chat)",
                content: String(content.prefix(8000))
            ))
        }
        result.cursorJson = WorldCursor.encode(Cursor(lastRowid: newest))
        return result
    }

    func openReadOnly() throws -> DatabaseQueue {
        try ForeignSQLite.openReadOnly(chatDB, copyName: "chat", scratch: scratchDirectory)
    }

    /// Returns recoverable messages plus the max ROWID actually scanned (which
    /// may exceed the last recoverable message's rowid).
    static func fetch(_ queue: DatabaseQueue, after rowid: Int64) async throws -> ([RawMessage], Int64) {
        try await queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT m.ROWID AS rowid, m.text AS text, m.attributedBody AS body,
                       m.date AS date, m.is_from_me AS from_me,
                       h.id AS sender, COALESCE(c.display_name, c.chat_identifier) AS chat
                FROM message m
                LEFT JOIN handle h ON h.ROWID = m.handle_id
                JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
                JOIN chat c ON c.ROWID = cmj.chat_id
                WHERE m.ROWID > ? AND m.associated_message_type = 0
                ORDER BY m.ROWID LIMIT ?
                """, arguments: [rowid, maxPerSync])
            let scannedMax = rows.map { $0["rowid"] as Int64 }.max() ?? rowid
            let messages = rows.compactMap { row -> RawMessage? in
                var text: String? = row["text"]
                if text == nil || text?.isEmpty == true, let body: Data = row["body"] {
                    text = Typedstream.extractText(body)
                }
                guard let text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                let chat: String? = row["chat"]
                let ns: Int64 = row["date"]
                return RawMessage(rowid: row["rowid"], chat: chat ?? "unknown",
                                  sender: row["sender"], isFromMe: (row["from_me"] as Int64? ?? 0) == 1,
                                  date: AppleEpoch.date(fromNanoseconds: ns), text: text)
            }
            return (messages, scannedMax)
        }
    }
}

/// Best-effort typedstream text recovery: take the longest printable UTF-8 run
/// that isn't an archiver class name. ponytail: real typedstream parsing if
/// coverage proves too low.
enum Typedstream {
    static let knownNoise: Set<String> = [
        "NSString", "NSMutableString", "NSAttributedString", "NSMutableAttributedString",
        "NSObject", "NSDictionary", "NSNumber", "NSValue", "streamtyped",
        "__kIMMessagePartAttributeName", "__kIMFileTransferGUIDAttributeName",
        "__kIMBaseWritingDirectionAttributeName", "NSData",
    ]

    static func extractText(_ data: Data) -> String? {
        var best: String?
        var run: [UInt8] = []

        func flush() {
            guard run.count >= 3 else { run = []; return }
            let candidate = String(decoding: run, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            run = []
            guard candidate.count >= 3, !knownNoise.contains(candidate),
                  !candidate.hasPrefix("__kIM"), !candidate.hasPrefix("NS") else { return }
            if candidate.count > (best?.count ?? 0) { best = candidate }
        }

        for byte in data {
            // printable ASCII + UTF-8 continuation/lead bytes + newline/tab
            if byte >= 0x20 && byte != 0x7F || byte == 0x0A || byte == 0x09 || byte >= 0x80 {
                run.append(byte)
            } else {
                flush()
            }
        }
        flush()
        return best
    }
}
