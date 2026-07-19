import Foundation
import GRDB
import JStore

/// Gates proactive nudges: global cooldown between any two nudges, a per-topic
/// dedup window, and a daily cap. Backed by the `nudge` table.
public struct NudgeFunnel: Sendable {
    private let database: JarvisDatabase

    public var globalCooldown: TimeInterval = 20 * 60 // ≥20 min between nudges
    public var dedupWindow: TimeInterval = 24 * 3600  // same topic at most once/day
    public var dailyCap: Int = 8

    public init(database: JarvisDatabase) { self.database = database }

    /// True if a nudge with this dedup key may be delivered now.
    public func canDeliver(dedupKey: String?, now: Date = .now) async -> Bool {
        (try? await database.reader.read { db -> Bool in
            if let last = try NudgeRow.order(Column("created_at").desc).fetchOne(db),
               now.timeIntervalSince(last.createdAt) < globalCooldown {
                return false
            }
            let dayAgo = now.addingTimeInterval(-86400)
            let todayCount = try NudgeRow.filter(Column("created_at") >= dayAgo).fetchCount(db)
            if todayCount >= dailyCap { return false }
            if let dedupKey {
                let window = now.addingTimeInterval(-dedupWindow)
                let dup = try NudgeRow
                    .filter(Column("dedup_key") == dedupKey && Column("created_at") >= window)
                    .fetchCount(db)
                if dup > 0 { return false }
            }
            return true
        }) ?? false
    }

    public func record(_ nudge: NudgeRow) async {
        _ = try? await database.writer.write { try nudge.insert($0) }
    }

    public func recent(limit: Int = 30) async -> [NudgeRow] {
        (try? await database.reader.read { db in
            try NudgeRow.order(Column("created_at").desc).limit(limit).fetchAll(db)
        }) ?? []
    }
}
