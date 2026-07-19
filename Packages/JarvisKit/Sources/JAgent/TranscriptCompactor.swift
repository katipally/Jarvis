import Foundation

/// Context-window compaction: when the transcript approaches the model's limit,
/// the middle of the conversation is folded into one summary message. Planning
/// is pure and testable; the caller produces the summary text (model call or
/// static fallback) and rebuilds the transcript as head + summary + tail.
public enum TranscriptCompactor {
    public struct Plan: Sendable {
        /// Protected opening turn (kept verbatim).
        public let head: [NeutralMessage]
        /// Messages to fold into a summary.
        public let middle: [NeutralMessage]
        /// Protected recent turns; always starts at a plain user turn so a
        /// tool_use is never severed from its results.
        public let tail: [NeutralMessage]
    }

    /// Rough chars→tokens factor used for pressure estimates.
    static let charsPerToken = 4
    /// Compact once the estimate passes this share of the context window.
    static let pressureThreshold = 0.8
    /// Recent messages kept verbatim (extended backward to a clean boundary).
    static let protectedTailCount = 8

    /// Token-pressure estimate for a pending request: transcript + tool schemas
    /// (the schemas ride in every request and are not free).
    public static func estimatedTokens(_ messages: [NeutralMessage], toolSchemas: [ToolSchema] = []) -> Int {
        let messageChars = messages.reduce(0) { $0 + size($1) }
        let schemaChars = toolSchemas.reduce(0) {
            $0 + $1.name.count + $1.description.count + $1.parameters.jsonString.count
        }
        return (messageChars + schemaChars) / charsPerToken
    }

    /// Returns nil when compaction isn't needed — or isn't possible without
    /// splitting a tool pair.
    public static func plan(
        _ messages: [NeutralMessage],
        contextLimit: Int,
        toolSchemas: [ToolSchema] = []
    ) -> Plan? {
        let pressure = estimatedTokens(messages, toolSchemas: toolSchemas)
        guard pressure > Int(Double(contextLimit) * pressureThreshold) else { return nil }
        guard messages.count > protectedTailCount + 2 else { return nil }

        var tailStart = messages.count - protectedTailCount
        while tailStart > 1, !isPlainUserTurn(messages[tailStart]) { tailStart -= 1 }
        guard tailStart > 1 else { return nil } // no clean boundary → skip

        return Plan(
            head: Array(messages[..<1]),
            middle: Array(messages[1..<tailStart]),
            tail: Array(messages[tailStart...])
        )
    }

    /// Render the middle turns as summarizer input, truncated so the summary
    /// call itself can't blow up.
    public static func renderForSummary(
        _ messages: [NeutralMessage],
        perMessageCap: Int = 500,
        totalCap: Int = 20_000
    ) -> String {
        var lines: [String] = []
        var total = 0
        for message in messages {
            var parts: [String] = []
            for block in message.content {
                switch block {
                case .text(let t): parts.append(t)
                case .thinking: break // reasoning is not conversation content
                case .image: parts.append("[image]")
                case .toolUse(_, let name, _): parts.append("[called \(name)]")
                case .toolResult(_, let content, let isError, _):
                    parts.append(isError ? "[tool error: \(content.prefix(120))]" : "[tool result: \(content.prefix(200))]")
                }
            }
            let text = parts.joined(separator: " ").prefix(perMessageCap)
            guard !text.isEmpty else { continue }
            let line = "\(message.role == .user ? "User" : "Assistant"): \(text)"
            total += line.count
            if total > totalCap { break }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    /// A user turn carrying no tool results — the only safe cut boundary.
    public static func isPlainUserTurn(_ message: NeutralMessage) -> Bool {
        message.role == .user && !message.content.contains {
            if case .toolResult = $0 { return true }
            return false
        }
    }

    static func size(_ message: NeutralMessage) -> Int {
        message.content.reduce(0) { $0 + blockSize($1) }
    }

    private static func blockSize(_ block: ContentBlock) -> Int {
        switch block {
        case .text(let t): t.count
        case .thinking(let t, _): t.count
        case .image: 6000 // rough token-equivalent of one attached image
        case .toolUse(_, _, let input): input.jsonString.count
        case .toolResult(_, let content, _, let images): content.count + images.count * 6000
        }
    }
}
