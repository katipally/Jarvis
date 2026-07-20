import CryptoKit
import Foundation

/// Staged, content-key-deduped time-based delivery (openhuman planner/plan.rs):
/// meetings escalate heads_up → final_call → starting_now; commitments soon →
/// due. Each (category, overlap key, stage) fires at most once — the caller
/// checks `stableKey` against the delivery_state table with INSERT OR IGNORE.
public enum DeliveryPlanner {
    public struct Event: Sendable {
        public var category: String // "meeting" | "commitment"
        public var overlapKey: String // stable identity across ticks (title+time bucket / commitment id)
        public var title: String
        public var at: Date

        public init(category: String, overlapKey: String, title: String, at: Date) {
            self.category = category
            self.overlapKey = overlapKey
            self.title = title
            self.at = at
        }
    }

    public struct Planned: Sendable, Equatable {
        public var dedupeKey: String
        public var category: String
        public var overlapKey: String
        public var stage: String
        public var title: String
        public var body: String
    }

    public static func stableKey(category: String, overlapKey: String, stage: String) -> String {
        let digest = SHA256.hash(data: Data("\(category)|\(overlapKey)|\(stage)".utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Which stage (if any) each event is in right now.
    public static func plan(events: [Event], lookahead: TimeInterval = 3600, now: Date = .now) -> [Planned] {
        var out: [Planned] = []
        for event in events {
            let minutes = event.at.timeIntervalSince(now) / 60
            let stage: String?
            let body: String?
            switch event.category {
            case "meeting":
                if minutes > 10, minutes <= lookahead / 60 {
                    stage = "heads_up"
                    body = "\(event.title) at \(event.at.formatted(date: .omitted, time: .shortened))."
                } else if minutes > 0, minutes <= 10 {
                    stage = "final_call"
                    body = "\(event.title) starts in \(max(1, Int(minutes))) min."
                } else if minutes > -10, minutes <= 0 {
                    stage = "starting_now"
                    body = "\(event.title) is starting now."
                } else {
                    stage = nil; body = nil
                }
            case "commitment":
                if minutes > 0, minutes <= 15 {
                    stage = "soon"
                    body = "You said you'd \(event.title) by \(event.at.formatted(date: .omitted, time: .shortened))."
                } else if minutes > -60, minutes <= 0 {
                    stage = "due"
                    body = "Due now: you said you'd \(event.title)."
                } else {
                    stage = nil; body = nil
                }
            default:
                stage = nil; body = nil
            }
            if let stage, let body {
                out.append(Planned(
                    dedupeKey: stableKey(category: event.category, overlapKey: event.overlapKey, stage: stage),
                    category: event.category, overlapKey: event.overlapKey, stage: stage,
                    title: event.category == "meeting" ? "Meeting" : "Reminder",
                    body: body
                ))
            }
        }
        return out
    }
}
