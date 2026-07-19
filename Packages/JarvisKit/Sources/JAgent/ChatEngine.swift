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

/// Accumulates streaming deltas into a final assistant `NeutralMessage`.
struct MessageAssembler {
    private var text = ""
    private var thinking = ""
    private var toolOrder: [String] = []
    private var toolNames: [String: String] = [:]
    private var toolInputs: [String: String] = [:]

    mutating func appendText(_ t: String) { text += t }
    mutating func appendThinking(_ t: String) { thinking += t }

    mutating func startTool(id: String, name: String) {
        if toolNames[id] == nil { toolOrder.append(id) }
        toolNames[id] = name
        if toolInputs[id] == nil { toolInputs[id] = "" }
    }

    mutating func appendToolInput(id: String, fragment: String) {
        toolInputs[id, default: ""] += fragment
    }

    mutating func endTool(id: String) { /* input finalized on message() */ }

    func message() -> NeutralMessage {
        var blocks: [ContentBlock] = []
        if !thinking.isEmpty { blocks.append(.thinking(thinking)) }
        if !text.isEmpty { blocks.append(.text(text)) }
        for id in toolOrder {
            let input = JSONValue.parse(toolInputs[id] ?? "") ?? .object([:])
            blocks.append(.toolUse(id: id, name: toolNames[id] ?? "", input: input))
        }
        if blocks.isEmpty { blocks.append(.text("")) }
        return NeutralMessage(role: .assistant, content: blocks)
    }
}
