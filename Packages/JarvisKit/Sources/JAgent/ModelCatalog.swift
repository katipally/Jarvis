import Foundation

/// Capability metadata for one model, distilled from models.dev.
public struct ModelInfo: Sendable, Codable, Equatable {
    public var id: String
    public var name: String?
    public var contextLimit: Int?
    public var reasoning: Bool
    public var supportsTools: Bool
    public var inputModalities: [String]

    public var supportsVision: Bool { inputModalities.contains("image") }

    public init(
        id: String,
        name: String? = nil,
        contextLimit: Int? = nil,
        reasoning: Bool = false,
        supportsTools: Bool = false,
        inputModalities: [String] = ["text"]
    ) {
        self.id = id
        self.name = name
        self.contextLimit = contextLimit
        self.reasoning = reasoning
        self.supportsTools = supportsTools
        self.inputModalities = inputModalities
    }
}

/// Live model capability catalog from https://models.dev/api.json, cached to disk.
/// No hardcoded model lists — everything is fetched.
public actor ModelCatalog {
    public static let apiURL = URL(string: "https://models.dev/api.json")!

    private let cacheURL: URL
    private let session: URLSession
    private var byProvider: [String: [String: ModelInfo]] = [:]
    private var loaded = false

    public init(cacheDirectory: URL, session: URLSession = .shared) {
        self.cacheURL = cacheDirectory.appendingPathComponent("models-dev.json")
        self.session = session
    }

    /// Look up capabilities; loads the disk cache lazily on first use.
    public func info(provider: String, model: String) async -> ModelInfo? {
        if !loaded { loadFromDisk() }
        if let exact = byProvider[provider]?[model] { return exact }
        // Fall back to a suffix match (providers sometimes prefix ids).
        if let models = byProvider[provider] {
            if let hit = models.first(where: { model.hasSuffix($0.key) || $0.key.hasSuffix(model) }) {
                return hit.value
            }
        }
        return nil
    }

    /// Fetch the freshest catalog from the network and update the disk cache.
    public func refresh() async {
        guard let (data, response) = try? await session.data(from: Self.apiURL),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            if !loaded { loadFromDisk() }
            return
        }
        try? data.write(to: cacheURL)
        parse(data)
        loaded = true
    }

    private func loadFromDisk() {
        loaded = true
        guard let data = try? Data(contentsOf: cacheURL) else { return }
        parse(data)
    }

    private func parse(_ data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        var result: [String: [String: ModelInfo]] = [:]
        for (providerID, providerValue) in root {
            guard let providerObj = providerValue as? [String: Any],
                  let models = providerObj["models"] as? [String: Any] else { continue }
            var infos: [String: ModelInfo] = [:]
            for (modelID, modelValue) in models {
                guard let m = modelValue as? [String: Any] else { continue }
                infos[modelID] = ModelInfo(
                    id: modelID,
                    name: m["name"] as? String,
                    contextLimit: (m["limit"] as? [String: Any])?["context"] as? Int,
                    reasoning: truthy(m["reasoning"]),
                    supportsTools: truthy(m["tool_call"]),
                    inputModalities: (m["modalities"] as? [String: Any])?["input"] as? [String] ?? ["text"]
                )
            }
            result[providerID] = infos
        }
        byProvider = result
    }

    /// models.dev encodes some capabilities as bool and some as an object.
    private func truthy(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        if value is [String: Any] { return true }
        return false
    }
}
