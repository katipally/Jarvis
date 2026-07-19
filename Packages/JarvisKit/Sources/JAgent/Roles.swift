import Foundation

/// Task categories that can each be routed to a different provider/model.
/// The harness is neutral: no role has a default model.
public enum AgentRole: String, Sendable, Codable, CaseIterable, Identifiable {
    case brain      // chat + tools
    case aux        // extraction, nudge decisions, compaction, summaries
    case embeddings // semantic memory (may be Apple on-device instead)

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .brain: "Brain"
        case .aux: "Auxiliary"
        case .embeddings: "Embeddings"
        }
    }

    public var detail: String {
        switch self {
        case .brain: "Chat and tool use"
        case .aux: "Extraction, summaries, proactivity checks"
        case .embeddings: "Semantic memory search"
        }
    }
}

/// Which provider/model handles a role. Persisted in `setting`.
public struct RoleAssignment: Sendable, Codable, Equatable {
    public var providerAccountId: String
    public var modelId: String
    public var reasoningEffort: ReasoningEffort?

    public init(providerAccountId: String, modelId: String, reasoningEffort: ReasoningEffort? = nil) {
        self.providerAccountId = providerAccountId
        self.modelId = modelId
        self.reasoningEffort = reasoningEffort
    }
}

/// Everything needed to construct a concrete adapter for one call.
public struct ProviderSpec: Sendable {
    public enum API: String, Sendable, Codable, CaseIterable {
        case anthropicMessages
        case openaiResponses
        case openaiCompat
    }

    public var api: API
    public var apiKey: String
    public var baseURL: URL

    public init(api: API, apiKey: String, baseURL: URL) {
        self.api = api
        self.apiKey = apiKey
        self.baseURL = baseURL
    }
}

public enum ProviderFactory {
    public static func make(_ spec: ProviderSpec, session: URLSession = .shared) -> any ProviderAdapter {
        switch spec.api {
        case .anthropicMessages:
            AnthropicAdapter(apiKey: spec.apiKey, baseURL: spec.baseURL, session: session)
        case .openaiResponses:
            OpenAIResponsesAdapter(apiKey: spec.apiKey, baseURL: spec.baseURL, session: session)
        case .openaiCompat:
            OpenAICompatAdapter(apiKey: spec.apiKey, baseURL: spec.baseURL, session: session)
        }
    }
}

/// Sensible defaults per known provider — all user-overridable in Settings.
public enum ProviderPreset {
    public static func defaultAPI(for provider: String) -> ProviderSpec.API {
        switch provider {
        case "anthropic", "minimax": .anthropicMessages
        case "openai": .openaiResponses
        default: .openaiCompat
        }
    }

    public static func defaultBaseURL(for provider: String) -> URL {
        switch provider {
        case "anthropic": URL(string: "https://api.anthropic.com")!
        case "minimax": URL(string: "https://api.minimax.io/anthropic")!
        case "openai": URL(string: "https://api.openai.com")!
        default: URL(string: "https://api.openai.com")!
        }
    }

    /// models.dev provider id for capability lookup.
    public static func catalogProviderID(for provider: String) -> String { provider }
}
