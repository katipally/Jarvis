import Foundation
import GRDB
import JKnowledge

/// Apple Notes via NoteStore.sqlite (needs Full Disk Access). Title + snippet
/// only — the full body is a reverse-engineered protobuf, deliberately skipped
/// in v1. Cursor = MAX(ZMODIFICATIONDATE1); an edited note re-ingests as a new
/// episode (external_id carries the mtime).
public struct NotesWorld: WorldConnector {
    public let worldId = "notes"
    let noteStore: URL
    let scratchDirectory: URL

    public init(noteStore: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.apple.notes/NoteStore.sqlite"),
        scratchDirectory: URL) {
        self.noteStore = noteStore
        self.scratchDirectory = scratchDirectory
    }

    struct Cursor: Codable {
        var lastModified: Double = 0 // Core Data epoch seconds
    }

    public func sync(cursorJson: String?) async throws -> WorldSyncResult {
        guard FileManager.default.isReadableFile(atPath: noteStore.path) else {
            throw WorldError.needsFullDiskAccess
        }
        let old = WorldCursor.decode(cursorJson, as: Cursor.self) ?? Cursor()
        let queue = try openReadOnly()

        let sql = """
            SELECT Z_PK AS pk, ZTITLE1 AS title, ZSNIPPET AS snippet,
                   ZMODIFICATIONDATE1 AS modified
            FROM ZICCLOUDSYNCINGOBJECT
            WHERE ZTITLE1 IS NOT NULL AND ZMODIFICATIONDATE1 > ?
            ORDER BY ZMODIFICATIONDATE1 LIMIT 200
            """
        let rows = try queue.read { db in
            try Row.fetchAll(db, sql: sql, arguments: [old.lastModified])
        }

        var result = WorldSyncResult()
        var newest = old.lastModified
        for row in rows {
            let modified: Double = row["modified"]
            newest = max(newest, modified)
            let title: String = row["title"]
            let snippet: String? = row["snippet"]
            let content = ["Note: \(title)", snippet ?? ""]
                .filter { !$0.isEmpty }.joined(separator: "\n")
            guard content.count > 12 else { continue }
            let pk: Int64 = row["pk"]
            result.episodes.append(EpisodeDraft(
                externalId: "note:\(pk):\(Int(modified))",
                occurredAt: AppleEpoch.date(fromSeconds: modified),
                title: title, content: content
            ))
        }
        result.cursorJson = WorldCursor.encode(Cursor(lastModified: newest))
        return result
    }

    func openReadOnly() throws -> DatabaseQueue {
        try ForeignSQLite.openReadOnly(noteStore, copyName: "notes", scratch: scratchDirectory)
    }
}
