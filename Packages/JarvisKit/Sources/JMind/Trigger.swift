import Foundation

/// An external event that might deserve the agent's attention: a new email,
/// a calendar change, a context switch. Normalized before any model sees it.
public struct Trigger: Sendable {
    /// Rate-limit family — one flooding source can't starve the others.
    public var source: String // mail | imessage | calendar | context_switch | meeting | world
    public var dedupeKey: String
    /// Short REDACTED summary shown to the triage classifier (never the raw
    /// third-party payload — anti-exfiltration, openhuman gate.rs).
    public var gateSummary: String
    /// Full content, re-attached only past the gate for react/escalate.
    public var content: String
    public var receivedAt: Date

    public init(source: String, dedupeKey: String, gateSummary: String,
                content: String = "", receivedAt: Date = .now) {
        self.source = source
        self.dedupeKey = dedupeKey
        self.gateSummary = gateSummary
        self.content = content
        self.receivedAt = receivedAt
    }
}

/// The 4-way triage verdict (openhuman trigger_triage): bias-to-drop.
public enum TriageAction: String, Sendable, CaseIterable {
    case drop, acknowledge, react, escalate

    /// Tolerant parse for small-model output: case-insensitive, substring
    /// match, garbage → .drop (over-escalating wastes agent time).
    public static func parse(_ raw: String) -> TriageAction {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let exact = TriageAction(rawValue: lower) { return exact }
        for action in [TriageAction.escalate, .react, .acknowledge, .drop]
            where lower.contains(action.rawValue) { return action }
        return .drop
    }
}

/// What the pipeline decided to do with a trigger. Note: the trigger's
/// CONTENT is never lost either way — text sources are already indexed as
/// episodes by the world sync; the verdict only decides whether the agent
/// REACTS. acknowledge = logged as seen, no reaction.
public enum GateDecision: Sendable, Equatable {
    case drop(acknowledge: Bool)
    case promote(escalated: Bool)

    public static func from(_ action: TriageAction) -> GateDecision {
        switch action {
        case .drop: .drop(acknowledge: false)
        case .acknowledge: .drop(acknowledge: true)
        case .react: .promote(escalated: false)
        case .escalate: .promote(escalated: true)
        }
    }
}
