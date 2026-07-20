import Foundation

/// Deterministic quality gate for MODEL-extracted facts. The on-device 3B model
/// sometimes echoes chit-chat back as "facts" ("Can you hear me?") or records
/// meta/transient observations; prompts reduce that but can't eliminate it, so
/// every extracted fact passes this filter before storage. Explicit `remember`
/// commands bypass it — a direct instruction always wins.
public enum FactValidator {
    // ponytail: keyword heuristics; upgrade to an on-device CRITIC pass if the junk rate stays high.

    private static let chitchatPrefixes = [
        "hello", "hi ", "hi!", "hi,", "hey", "thanks", "thank you", "ok ", "okay",
        "good morning", "good afternoon", "good evening", "good night", "test ", "testing",
        "can you hear", "are you there",
    ]

    private static let metaPhrases = [
        "engaging with jarvis", "talking to jarvis", "talking to the assistant",
        "chatting with", "interacting with", "conversing with", "using the assistant",
        "asked the assistant", "is testing the", "this conversation", "notch-side assistant",
        "can hear the user", "voice input works", "microphone works",
    ]

    private static let transientPhrases = [
        "unstaged", "uncommitted", "working directory", "frontmost", "on their screen",
        "currently open", "clipboard", "right now", "at the moment", "just opened", "just closed",
    ]

    /// True when `text` reads like a durable, user-specific fact. Pass the
    /// episode content as `source` when available: a fact appearing verbatim in
    /// the source is a quote, not a distillation.
    public static func isDurable(_ text: String, source: String? = nil) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12, !trimmed.hasSuffix("?") else { return false }
        guard trimmed.split(separator: " ").count >= 4 else { return false }

        let lower = trimmed.lowercased()
        if chitchatPrefixes.contains(where: { lower.hasPrefix($0) }) { return false }
        if metaPhrases.contains(where: { lower.contains($0) }) { return false }
        if transientPhrases.contains(where: { lower.contains($0) }) { return false }
        if let source, source.lowercased().contains(lower) { return false }
        return true
    }

    /// Entity names that are conversation roles, not real-world entities.
    /// Self-references ("me", "user") are NOT rejected here — GraphWriter maps
    /// them to the single is_self node before this check matters.
    public static func isRealEntity(_ name: String) -> Bool {
        let lower = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty, lower.count < 60 else { return false }
        return !["assistant", "the assistant", "jarvis", "you"].contains(lower)
    }

    /// Token-set Jaccard similarity (Hive's memory dedup, 0.82 threshold).
    public static func jaccard(_ a: String, _ b: String) -> Double {
        let ta = Set(queryTokens(a)), tb = Set(queryTokens(b))
        guard !ta.isEmpty, !tb.isEmpty else { return 0 }
        return Double(ta.intersection(tb).count) / Double(ta.union(tb).count)
    }
}
