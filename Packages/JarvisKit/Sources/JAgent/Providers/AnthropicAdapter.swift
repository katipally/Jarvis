import Foundation

/// Anthropic Messages API adapter. Also serves MiniMax (Anthropic-compatible)
/// via a base-URL override, e.g. https://api.minimax.io/anthropic.
public struct AnthropicAdapter: ProviderAdapter {
    public let baseURL: URL
    public let apiKey: String
    public let anthropicVersion: String
    private let session: URLSession

    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.anthropic.com")!,
        anthropicVersion: String = "2023-06-01",
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.anthropicVersion = anthropicVersion
        self.session = session
    }

    private func request(path: String, method: String) -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        return req
    }

    // MARK: - Streaming

    public func stream(_ modelRequest: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = self.request(path: "v1/messages", method: "POST")
                    let body = Self.buildBody(modelRequest)
                    if modelRequest.reasoningEffort != nil {
                        req.setValue("interleaved-thinking-2025-05-14", forHTTPHeaderField: "anthropic-beta")
                    }
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let bytes = try await ProviderTransport.openSSEStream(session: session, request: req)
                    var acc = SSEAccumulator()
                    var state = AnthropicStreamState()

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard let frame = acc.feed(line) else { continue }
                        try Self.handle(frame, state: &state, continuation: continuation)
                    }
                    if let frame = acc.flush() {
                        try Self.handle(frame, state: &state, continuation: continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func handle(
        _ frame: SSEFrame,
        state: inout AnthropicStreamState,
        continuation: AsyncThrowingStream<ModelStreamEvent, Error>.Continuation
    ) throws {
        guard let data = frame.data.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }

        switch type {
        case "message_start":
            if let message = obj["message"] as? [String: Any],
               let usage = message["usage"] as? [String: Any] {
                state.inputTokens = usage["input_tokens"] as? Int ?? 0
            }

        case "content_block_start":
            let index = obj["index"] as? Int ?? 0
            if let block = obj["content_block"] as? [String: Any],
               let blockType = block["type"] as? String {
                if blockType == "tool_use", let id = block["id"] as? String, let name = block["name"] as? String {
                    state.toolIDByIndex[index] = id
                    continuation.yield(.toolUseStart(id: id, name: name))
                }
            }

        case "content_block_delta":
            let index = obj["index"] as? Int ?? 0
            if let delta = obj["delta"] as? [String: Any], let deltaType = delta["type"] as? String {
                switch deltaType {
                case "text_delta":
                    if let text = delta["text"] as? String { continuation.yield(.textDelta(text)) }
                case "thinking_delta":
                    if let thinking = delta["thinking"] as? String { continuation.yield(.thinkingDelta(thinking)) }
                case "input_json_delta":
                    if let partial = delta["partial_json"] as? String, let id = state.toolIDByIndex[index] {
                        continuation.yield(.toolInputDelta(id: id, jsonFragment: partial))
                    }
                default:
                    break
                }
            }

        case "content_block_stop":
            let index = obj["index"] as? Int ?? 0
            if let id = state.toolIDByIndex[index] {
                continuation.yield(.toolUseEnd(id: id))
            }

        case "message_delta":
            if let delta = obj["delta"] as? [String: Any], let reason = delta["stop_reason"] as? String {
                state.stopReason = mapStop(reason)
            }
            if let usage = obj["usage"] as? [String: Any] {
                state.outputTokens = usage["output_tokens"] as? Int ?? state.outputTokens
            }

        case "message_stop":
            continuation.yield(.usage(Usage(inputTokens: state.inputTokens, outputTokens: state.outputTokens)))
            continuation.yield(.stop(state.stopReason))

        case "error":
            let message = (obj["error"] as? [String: Any])?["message"] as? String ?? "unknown error"
            throw ProviderError.stream(message: message)

        default:
            break // ping, etc.
        }
    }

    private static func mapStop(_ raw: String) -> StopReason {
        switch raw {
        case "end_turn": .endTurn
        case "tool_use": .toolUse
        case "max_tokens": .maxTokens
        case "stop_sequence": .stopSequence
        case "refusal": .refusal
        default: .other
        }
    }

    // MARK: - Body

    static func buildBody(_ req: ModelRequest) -> [String: Any] {
        var body: [String: Any] = [
            "model": req.model,
            "stream": true,
            "messages": req.messages.map(messageJSON),
        ]

        var maxTokens = req.maxTokens
        if let effort = req.reasoningEffort {
            let budget = effort.anthropicBudget
            maxTokens = max(maxTokens, budget + 4096)
            body["thinking"] = ["type": "enabled", "budget_tokens": budget]
        } else if let temp = req.temperature {
            body["temperature"] = temp
        }
        body["max_tokens"] = maxTokens

        if let system = req.system, !system.isEmpty {
            body["system"] = system
        }
        if !req.tools.isEmpty {
            body["tools"] = req.tools.map { tool in
                ["name": tool.name, "description": tool.description, "input_schema": tool.parameters.anyValue]
            }
        }
        return body
    }

    private static func messageJSON(_ message: NeutralMessage) -> [String: Any] {
        // Anthropic has only user/assistant roles; tool results ride inside a user turn.
        let role = (message.role == .assistant) ? "assistant" : "user"
        let blocks = message.content.compactMap(blockJSON)
        return ["role": role, "content": blocks]
    }

    private static func blockJSON(_ block: ContentBlock) -> [String: Any]? {
        switch block {
        case .text(let t):
            return ["type": "text", "text": t]
        case .thinking:
            return nil // thinking blocks are not replayed without their signature
        case .image(let img):
            return ["type": "image", "source": ["type": "base64", "media_type": img.mediaType, "data": img.base64Data]]
        case .toolUse(let id, let name, let input):
            return ["type": "tool_use", "id": id, "name": name, "input": input.anyValue]
        case .toolResult(let toolUseId, let content, let isError, let images):
            var resultContent: [[String: Any]] = [["type": "text", "text": content]]
            for image in images {
                resultContent.append(["type": "image", "source": ["type": "base64", "media_type": image.mediaType, "data": image.base64Data]])
            }
            return ["type": "tool_result", "tool_use_id": toolUseId, "content": resultContent, "is_error": isError]
        }
    }

    // MARK: - Models

    public func listModels() async throws -> [ProviderModel] {
        var req = request(path: "v1/models", method: "GET")
        req.setValue("100", forHTTPHeaderField: "limit")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return []
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["data"] as? [[String: Any]] else { return [] }
        return models.compactMap { m in
            guard let id = m["id"] as? String else { return nil }
            return ProviderModel(id: id, displayName: m["display_name"] as? String)
        }
    }
}

private struct AnthropicStreamState {
    var inputTokens = 0
    var outputTokens = 0
    var stopReason: StopReason = .endTurn
    var toolIDByIndex: [Int: String] = [:]
}
