import Foundation
import GRDB
import JStore

/// Persisted dismissal backoff for the funnel. When the user dismisses a nudge
/// the cooldown multiplier jumps 4x (Jarvis was too chatty); it decays back
/// toward 1 as days pass with no dismissal. Stored in SettingsStore under
/// "funnel_state" by the caller — this type only holds the pure math so it stays
/// unit-testable and free of any store dependency.
public struct NudgeFunnelState: Codable, Sendable, Equatable {
    public var day: Date
    public var multiplier: Double

    public static let cap = 16.0

    public init(day: Date = .now, multiplier: Double = 1) {
        self.day = day
        self.multiplier = multiplier
    }

    /// A dismissal today: quadruple the cooldown multiplier (capped).
    public func bumped(now: Date = .now, calendar: Calendar = .current) -> NudgeFunnelState {
        NudgeFunnelState(day: calendar.startOfDay(for: now),
                         multiplier: min(multiplier * 4, Self.cap))
    }

    /// Halve the multiplier once per elapsed day (never below 1), so a quiet day
    /// walks the backoff back down. Idempotent within the same day.
    public func decayed(now: Date = .now, calendar: Calendar = .current) -> NudgeFunnelState {
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: day), to: today).day ?? 0
        guard days > 0 else { return self }
        let decayed = multiplier / pow(2, Double(days))
        return NudgeFunnelState(day: today, multiplier: max(1, decayed))
    }
}

/// Gates proactive nudges: global cooldown between any two nudges, a per-topic
/// dedup window, and a daily cap. Backed by the `nudge` table. `dailyCap`,
/// `globalCooldown`, and `cooldownMultiplier` are tuned per-call from the
/// aggressiveness setting + dismissal backoff before `canDeliver` runs.
public struct NudgeFunnel: Sendable {
    private let database: JarvisDatabase

    public var globalCooldown: TimeInterval = 20 * 60 // ≥20 min between nudges
    public var dedupWindow: TimeInterval = 24 * 3600  // same topic at most once/day
    public var dailyCap: Int = 8
    /// Scales the global cooldown up after dismissals (see NudgeFunnelState).
    public var cooldownMultiplier: Double = 1

    public init(database: JarvisDatabase) { self.database = database }

    /// True if a nudge with this dedup key may be delivered now.
    /// Suppressed rows (CRITIC-vetoed drafts recorded for the Activity
    /// timeline) are excluded from every check — only DELIVERED nudges may
    /// consume the cooldown, the daily cap, or the dedup window.
    public func canDeliver(dedupKey: String?, now: Date = .now) async -> Bool {
        let cooldown = globalCooldown * max(1, cooldownMultiplier)
        return (try? await database.reader.read { db -> Bool in
            let delivered = NudgeRow.filter(Column("state") != "suppressed")
            if let last = try delivered.order(Column("created_at").desc).fetchOne(db),
               now.timeIntervalSince(last.createdAt) < cooldown {
                return false
            }
            let dayAgo = now.addingTimeInterval(-86400)
            let todayCount = try delivered.filter(Column("created_at") >= dayAgo).fetchCount(db)
            if todayCount >= dailyCap { return false }
            if let dedupKey {
                let window = now.addingTimeInterval(-dedupWindow)
                let dup = try delivered
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
