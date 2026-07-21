import Foundation

/// Risk classification that drives the approval gate.
public enum RiskTier: String, Sendable, Codable {
    case readOnly       // safe to auto-run (queries, reads)
    case externalEffect // mutates the world — needs approval
}

public struct ToolContext: Sendable {
    public let runID: String
    public let isBackground: Bool

    public init(runID: String, isBackground: Bool) {
        self.runID = runID
        self.isBackground = isBackground
    }
}

public struct ToolOutput: Sendable {
    public var content: String
    public var isError: Bool
    /// Images to hand back to the model (e.g. recalled screen frames).
    public var images: [ImageSource]

    public init(_ content: String, isError: Bool = false, images: [ImageSource] = []) {
        self.content = content
        self.isError = isError
        self.images = images
    }
}

/// A runtime tool: its schema, risk tier, an optional per-invocation scope key
/// (e.g. target bundle id, so "Always allow for Notes" is possible), and its body.
public struct ToolSpec: Sendable {
    public let name: String
    public let description: String
    public let parameters: JSONValue
    public let tier: RiskTier
    /// Read-only tools that expose private user content (clipboard, screen
    /// pixels, app UI text). Excluded from unattended background runs.
    public let sensitive: Bool
    public let scopeKey: (@Sendable (JSONValue) -> String?)?
    public let summarize: (@Sendable (JSONValue) -> String)?
    public let run: @Sendable (JSONValue, ToolContext) async throws -> ToolOutput

    public init(
        name: String,
        description: String,
        parameters: JSONValue,
        tier: RiskTier,
        sensitive: Bool = false,
        scopeKey: (@Sendable (JSONValue) -> String?)? = nil,
        summarize: (@Sendable (JSONValue) -> String)? = nil,
        run: @escaping @Sendable (JSONValue, ToolContext) async throws -> ToolOutput
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.tier = tier
        self.sensitive = sensitive
        self.scopeKey = scopeKey
        self.summarize = summarize
        self.run = run
    }

    public var schema: ToolSchema {
        ToolSchema(name: name, description: description, parameters: parameters)
    }
}

/// An immutable set of tools. Background runs get a `.readOnlyOnly()` copy so
/// an autonomous turn can never invoke an external-effect tool.
public struct ToolRegistry: Sendable {
    private let tools: [String: ToolSpec]

    public init(_ specs: [ToolSpec]) {
        self.tools = Dictionary(specs.map { ($0.name, $0) }, uniquingKeysWith: { _, new in new })
    }

    public func tool(named name: String) -> ToolSpec? { tools[name] }

    public var schemas: [ToolSchema] { tools.values.map(\.schema) }

    public var isEmpty: Bool { tools.isEmpty }

    /// A compact catalog of the available tools for the system prompt: name +
    /// the first line of each description, sorted by name so the rendered prompt
    /// stays byte-identical across launches (the provider cache stays warm).
    /// Lets the prompt list tools straight from the registry instead of a
    /// hand-maintained, drift-prone hardcoded list.
    public var promptCatalog: String {
        tools.values
            .sorted { $0.name < $1.name }
            .map { spec in
                let firstLine = spec.description.split(separator: "\n", maxSplits: 1).first.map(String.init)
                    ?? spec.description
                return "- `\(spec.name)` — \(firstLine)"
            }
            .joined(separator: "\n")
    }

    /// The registry an unattended background run may hold: read-only tools that
    /// don't expose private user content (no clipboard, no screen, no app UI).
    public func readOnlyOnly() -> ToolRegistry {
        ToolRegistry(tools.values.filter { $0.tier == .readOnly && !$0.sensitive })
    }
}
