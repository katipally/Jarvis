import Foundation
import GRDB
import JKnowledge
import JStore

/// Internal world over the screen-rewind frames Jarvis already captures: only
/// context-switch frames with substantial OCR text feed extraction (noise
/// firewall), batched into one episode per sync. Cursor = last frame ts.
public struct ScreenWorld: WorldConnector {
    public let worldId = "screen"
    let database: JarvisDatabase

    public init(database: JarvisDatabase) {
        self.database = database
    }

    struct Cursor: Codable {
        var lastTs: Double = 0
    }

    static let minOCRChars = 200
    static let maxFramesPerSync = 20

    public func sync(cursorJson: String?) async throws -> WorldSyncResult {
        let old = WorldCursor.decode(cursorJson, as: Cursor.self)
        // First run starts at "now" — history was the old pipeline's job.
        guard let old else {
            return WorldSyncResult(cursorJson: WorldCursor.encode(Cursor(lastTs: Date().timeIntervalSince1970)))
        }

        let since = Date(timeIntervalSince1970: old.lastTs)
        let frames = try await database.reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT ts, app_name, window_title, ocr_text FROM screen_frame
                WHERE ts > ? AND trigger = 'context_switch' AND ocr_status = 'done'
                  AND LENGTH(ocr_text) > ?
                ORDER BY ts LIMIT ?
                """, arguments: [since, Self.minOCRChars, Self.maxFramesPerSync])
        }
        var result = WorldSyncResult()
        var newest = old.lastTs
        var sections: [String] = []
        for frame in frames {
            let ts: Date = frame["ts"]
            newest = max(newest, ts.timeIntervalSince1970)
            let app: String? = frame["app_name"]
            let title: String? = frame["window_title"]
            let ocr: String = frame["ocr_text"]
            sections.append("[\(app ?? "app")] \(title ?? "")\n\(ocr.prefix(500))")
        }
        if !sections.isEmpty {
            result.episodes.append(EpisodeDraft(
                externalId: "screen:\(Int(newest))",
                occurredAt: Date(timeIntervalSince1970: newest),
                title: "Screen activity",
                content: "Background screen text (low confidence, on-screen OCR):\n\n"
                    + sections.joined(separator: "\n---\n").prefix(6000)
            ))
        }
        result.cursorJson = WorldCursor.encode(Cursor(lastTs: newest))
        return result
    }
}
