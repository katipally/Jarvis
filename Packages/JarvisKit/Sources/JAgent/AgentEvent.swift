import Foundation

/// UI-facing "what happened" events. The engine emits these; renderers and the
/// transcript writer consume them. Kept separate from provider wire events.
public enum AgentEvent: Sendable {
    case runStarted
    case textDelta(String)
    case thinkingDelta(String)
    case toolCallStarted(id: String, name: String, input: JSONValue)
    case toolCallFinished(id: String, output: String, isError: Bool)
    case assistantMessage(NeutralMessage)
    case usage(Usage)
    case completed(StopReason)
    case failed(String)
    case aborted
}
