import Foundation

public enum ReasoningEffort: String, Sendable, Codable, CaseIterable {
    case minimal, low, medium, high, xhigh

    /// Anthropic extended-thinking token budget for this effort level.
    var anthropicBudget: Int {
        switch self {
        case .minimal: 1024
        case .low: 4096
        case .medium: 8192
        case .high: 16000
        case .xhigh: 32000
        }
    }
}

/// A tool made available to the model (JSON-schema parameters).
public struct ToolSchema: Sendable, Equatable {
    public var name: String
    public var description: String
    public var parameters: JSONValue // JSON Schema object

    public init(name: String, description: String, parameters: JSONValue) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

/// A model call, provider-neutral. Adapters translate this to their wire format.
public struct ModelRequest: Sendable {
    public var model: String
    public var system: String?
    public var messages: [NeutralMessage]
    public var tools: [ToolSchema]
    public var maxTokens: Int
    public var reasoningEffort: ReasoningEffort?
    public var temperature: Double?

    public init(
        model: String,
        system: String? = nil,
        messages: [NeutralMessage],
        tools: [ToolSchema] = [],
        maxTokens: Int = 4096,
        reasoningEffort: ReasoningEffort? = nil,
        temperature: Double? = nil
    ) {
        self.model = model
        self.system = system
        self.messages = messages
        self.tools = tools
        self.maxTokens = maxTokens
        self.reasoningEffort = reasoningEffort
        self.temperature = temperature
    }
}

public struct Usage: Sendable, Equatable {
    public var inputTokens: Int
    public var outputTokens: Int

    public init(inputTokens: Int = 0, outputTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

public enum StopReason: String, Sendable, Equatable {
    case endTurn, toolUse, maxTokens, stopSequence, refusal, other
}

/// The provider-neutral streaming vocabulary. Every adapter emits only these.
public enum ModelStreamEvent: Sendable, Equatable {
    case textDelta(String)
    case thinkingDelta(String)
    case toolUseStart(id: String, name: String)
    case toolInputDelta(id: String, jsonFragment: String)
    case toolUseEnd(id: String)
    case usage(Usage)
    case stop(StopReason)
}

/// A model as advertised by a provider's list endpoint.
public struct ProviderModel: Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String?

    public init(id: String, displayName: String? = nil) {
        self.id = id
        self.displayName = displayName
    }
}
