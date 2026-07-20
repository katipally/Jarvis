import Foundation
import GRDB
import JKnowledge

/// Browser history (Safari + Chrome, needs Full Disk Access). Deliberately
/// aggregate-only: no per-URL episodes (noise). Cumulative per-domain visit
/// counts live in the cursor; when a domain crosses the recurrence threshold
/// it's reported ONCE as a small browsing-pattern episode for extraction.
public struct BrowserWorld: WorldConnector {
    public let worldId = "browser"
    let safariHistory: URL
    let chromeHistory: URL
    let scratchDirectory: URL

    public init(safariHistory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Safari/History.db"),
        chromeHistory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome/Default/History"),
        scratchDirectory: URL) {
        self.safariHistory = safariHistory
        self.chromeHistory = chromeHistory
        self.scratchDirectory = scratchDirectory
    }

    struct Cursor: Codable {
        var safariLast: Double = 0 // seconds since 2001
        var chromeLast: Int64 = 0 // µs since 1601
        var counts: [String: Int] = [:]
        var noted: [String] = []
    }

    static let recurrenceThreshold = 25
    /// Search/utility domains that are traffic, not interest.
    static let stoplist: Set<String> = [
        "google.com", "www.google.com", "duckduckgo.com", "bing.com",
        "localhost", "127.0.0.1",
    ]

    public func sync(cursorJson: String?) async throws -> WorldSyncResult {
        let safariReadable = FileManager.default.isReadableFile(atPath: safariHistory.path)
        let chromeReadable = FileManager.default.isReadableFile(atPath: chromeHistory.path)
        guard safariReadable || chromeReadable else { throw WorldError.needsFullDiskAccess }

        var cursor = WorldCursor.decode(cursorJson, as: Cursor.self) ?? Cursor()
        let firstRun = cursor.safariLast == 0 && cursor.chromeLast == 0

        if safariReadable {
            try? syncSafari(&cursor, firstRun: firstRun)
        }
        if chromeReadable {
            try? syncChrome(&cursor, firstRun: firstRun)
        }

        var result = WorldSyncResult()
        for (domain, count) in cursor.counts
            where count >= Self.recurrenceThreshold && !cursor.noted.contains(domain) {
            cursor.noted.append(domain)
            result.episodes.append(EpisodeDraft(
                externalId: "browsing:\(domain)",
                occurredAt: .now,
                title: "Browsing pattern",
                content: "Browsing pattern: the user frequently visits \(domain) (\(count) recent visits)."
            ))
        }
        // Bound cursor growth: keep the busiest 300 domains.
        if cursor.counts.count > 300 {
            cursor.counts = Dictionary(uniqueKeysWithValues:
                cursor.counts.sorted { $0.value > $1.value }.prefix(300).map { ($0.key, $0.value) })
        }
        result.cursorJson = WorldCursor.encode(cursor)
        return result
    }

    private func syncSafari(_ cursor: inout Cursor, firstRun: Bool) throws {
        let queue = try Self.openCopy(of: safariHistory, name: "safari-history", in: scratchDirectory)
        // First run: only look back 7 days, don't count years of history.
        let since = firstRun ? Date().timeIntervalSinceReferenceDate - 7 * 86400 : cursor.safariLast
        let rows = try queue.inDatabase { db in
            try Row.fetchAll(db, sql: """
                SELECT hi.url AS url, hv.visit_time AS time
                FROM history_visits hv JOIN history_items hi ON hi.id = hv.history_item
                WHERE hv.visit_time > ? ORDER BY hv.visit_time LIMIT 5000
                """, arguments: [since])
        }
        for row in rows {
            let time: Double = row["time"]
            cursor.safariLast = max(cursor.safariLast, time)
            Self.count(row["url"], into: &cursor.counts)
        }
    }

    private func syncChrome(_ cursor: inout Cursor, firstRun: Bool) throws {
        let queue = try Self.openCopy(of: chromeHistory, name: "chrome-history", in: scratchDirectory)
        let since = firstRun
            ? Int64((Date().timeIntervalSince1970 - 7 * 86400 + 11_644_473_600) * 1_000_000)
            : cursor.chromeLast
        let rows = try queue.inDatabase { db in
            try Row.fetchAll(db, sql: """
                SELECT u.url AS url, v.visit_time AS time
                FROM visits v JOIN urls u ON u.id = v.url
                WHERE v.visit_time > ? ORDER BY v.visit_time LIMIT 5000
                """, arguments: [since])
        }
        for row in rows {
            let time: Int64 = row["time"]
            cursor.chromeLast = max(cursor.chromeLast, time)
            Self.count(row["url"], into: &cursor.counts)
        }
    }

    static func count(_ url: String?, into counts: inout [String: Int]) {
        guard let url, let host = URL(string: url)?.host()?.lowercased() else { return }
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        guard !stoplist.contains(domain), !domain.isEmpty else { return }
        counts[domain, default: 0] += 1
    }

    /// Browser DBs are locked while the browser runs — always read a copy.
    static func openCopy(of source: URL, name: String, in scratch: URL) throws -> DatabaseQueue {
        try ForeignSQLite.openReadOnly(source, copyName: name, scratch: scratch, directFirst: false)
    }
}
