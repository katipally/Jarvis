import Foundation

/// Deterministic quality gate for MODEL-extracted memories. The on-device 3B
/// model sometimes echoes chit-chat back as "facts" ("Can you hear me?") or
/// records meta/transient observations ("User is engaging with Jarvis"); the
/// prompts reduce that but can't eliminate it, so every extracted memory must
/// pass this filter before it is stored. Explicit `remember` commands from the
/// user bypass it — a direct instruction always wins.
public enum MemoryValidator {
    // ponytail: keyword heuristics; upgrade to an on-device CRITIC pass if the junk rate stays high.

    /// Prefixes that mark a message-shaped echo, not a distilled fact.
    private static let chitchatPrefixes = [
        "hello", "hi ", "hi!", "hi,", "hey", "thanks", "thank you", "ok ", "okay",
        "good morning", "good afternoon", "good evening", "good night", "test ", "testing",
        "can you hear", "are you there",
    ]

    /// Phrases that mean the "fact" is about this conversation/assistant session
    /// itself rather than about the user's life.
    private static let metaPhrases = [
        "engaging with jarvis", "talking to jarvis", "talking to the assistant",
        "chatting with", "interacting with", "conversing with", "using the assistant",
        "asked the assistant", "is testing the", "this conversation", "notch-side assistant",
        "can hear the user", "voice input works", "microphone works",
    ]

    /// Phrases that mark transient machine/session state — true now, stale in an hour.
    private static let transientPhrases = [
        "unstaged", "uncommitted", "working directory", "frontmost", "on their screen",
        "currently open", "clipboard", "right now", "at the moment", "just opened", "just closed",
    ]

    /// True when `text` reads like a durable, user-specific fact. Pass the
    /// conversation the memory was extracted from as `source` when available:
    /// a memory that appears verbatim in the source is a quote, not a fact.
    public static func isDurable(_ text: String, source: String? = nil) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Questions and fragments are never durable facts.
        guard trimmed.count >= 12, !trimmed.hasSuffix("?") else { return false }
        guard trimmed.split(separator: " ").count >= 4 else { return false }

        let lower = trimmed.lowercased()
        if chitchatPrefixes.contains(where: { lower.hasPrefix($0) }) { return false }
        if metaPhrases.contains(where: { lower.contains($0) }) { return false }
        if transientPhrases.contains(where: { lower.contains($0) }) { return false }

        // Verbatim echo of the user's own words = the model quoted instead of
        // distilling. Real memories are third-person rewrites.
        if let source, source.lowercased().contains(lower) { return false }

        return true
    }

    /// Entity names that are conversation roles, not real-world entities.
    public static func isRealEntity(_ name: String) -> Bool {
        let lower = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        return !["user", "the user", "assistant", "the assistant", "me", "you", "i"].contains(lower)
    }
}
