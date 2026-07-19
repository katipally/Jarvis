import Foundation

public enum ProviderError: Error, LocalizedError, Equatable {
    case invalidResponse
    case http(status: Int, body: String)
    case stream(message: String)
    case notConfigured(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The provider returned an invalid response."
        case .http(let status, let body):
            let snippet = body.count > 400 ? String(body.prefix(400)) + "…" : body
            return "Provider error (HTTP \(status)): \(snippet)"
        case .stream(let message):
            return "Streaming error: \(message)"
        case .notConfigured(let what):
            return "Not configured: \(what)"
        }
    }
}

/// The single seam every model provider implements. `stream` yields neutral
/// events; `listModels` powers the settings picker.
public protocol ProviderAdapter: Sendable {
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, Error>
    func listModels() async throws -> [ProviderModel]
}
