import Foundation

/// M1 single-turn streaming runner. Consumes one model stream and emits
/// `AgentEvent`s. M2 wraps this into the full tool loop; the event contract
/// is already tool-aware so the UI won't change.
public struct ChatEngine: Sendable {
    private let adapter: any ProviderAdapter

    public init(adapter: any ProviderAdapter) {
        self.adapter = adapter
    }

    public func run(_ request: ModelRequest) -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            let task = Task {
                continuation.yield(.runStarted)
                var assembler = MessageAssembler()
                do {
                    for try await event in adapter.stream(request) {
                        try Task.checkCancellation()
                        switch event {
                        case .textDelta(let t):
                            assembler.appendText(t)
                            continuation.yield(.textDelta(t))
                        case .thinkingDelta(let t):
                            assembler.appendThinking(t)
                            continuation.yield(.thinkingDelta(t))
                        case .thinkingSignature(let sig):
                            assembler.attachThinkingSignature(sig)
                        case .toolUseStart(let id, let name):
                            assembler.startTool(id: id, name: name)
                        case .toolInputDelta(let id, let fragment):
                            assembler.appendToolInput(id: id, fragment: fragment)
                        case .toolUseEnd(let id):
                            assembler.endTool(id: id)
                        case .usage(let usage):
                            continuation.yield(.usage(usage))
                        case .stop(let reason):
                            continuation.yield(.assistantMessage(assembler.message()))
                            continuation.yield(.completed(reason))
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.yield(.aborted)
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(error.localizedDescription))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Accumulates streaming deltas into a final assistant `NeutralMessage`,
/// preserving the arrival order of blocks (thinking/text/tool interleaving
/// matters when the turn is replayed to the provider).
struct MessageAssembler {
    private enum Part {
        case text(String)
        case thinking(String, signature: String?)
        case tool(id: String)
    }

    private var parts: [Part] = []
    private var toolNames: [String: String] = [:]
    private var toolInputs: [String: String] = [:]
    /// Tool ids whose input JSON failed to parse (e.g. truncated by max_tokens).
    private(set) var malformedToolIDs: Set<String> = []

    mutating func appendText(_ t: String) {
        if case .text(let existing) = parts.last {
            parts[parts.count - 1] = .text(existing + t)
        } else {
            parts.append(.text(t))
        }
    }

    mutating func appendThinking(_ t: String) {
        if case .thinking(let existing, let sig) = parts.last {
            parts[parts.count - 1] = .thinking(existing + t, signature: sig)
        } else {
            parts.append(.thinking(t, signature: nil))
        }
    }

    /// Attaches the provider's replay token to the most recent thinking block
    /// (creating an empty one if the provider sent no visible thinking text).
    mutating func attachThinkingSignature(_ signature: String) {
        if let index = parts.lastIndex(where: { if case .thinking = $0 { return true }; return false }),
           case .thinking(let text, _) = parts[index] {
            parts[index] = .thinking(text, signature: signature)
        } else {
            parts.append(.thinking("", signature: signature))
        }
    }

    mutating func startTool(id: String, name: String) {
        if toolNames[id] == nil { parts.append(.tool(id: id)) }
        toolNames[id] = name
        if toolInputs[id] == nil { toolInputs[id] = "" }
    }

    mutating func appendToolInput(id: String, fragment: String) {
        toolInputs[id, default: ""] += fragment
    }

    mutating func endTool(id: String) { /* input finalized on message() */ }

    mutating func message() -> NeutralMessage {
        var blocks: [ContentBlock] = []
        for part in parts {
            switch part {
            case .text(let t) where !t.isEmpty:
                blocks.append(.text(t))
            case .thinking(let t, let sig) where !t.isEmpty || sig != nil:
                blocks.append(.thinking(t, signature: sig))
            case .tool(let id):
                let raw = toolInputs[id] ?? ""
                let input: JSONValue
                if let parsed = JSONValue.parse(raw) {
                    input = parsed
                } else {
                    malformedToolIDs.insert(id)
                    input = .object([:])
                }
                blocks.append(.toolUse(id: id, name: toolNames[id] ?? "", input: input))
            default:
                break
            }
        }
        if blocks.isEmpty { blocks.append(.text("")) }
        return NeutralMessage(role: .assistant, content: blocks)
    }
}
