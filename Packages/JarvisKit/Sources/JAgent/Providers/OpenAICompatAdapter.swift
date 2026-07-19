import Foundation

/// OpenAI Chat Completions adapter for any OpenAI-compatible endpoint
/// (OpenAI legacy, Ollama, local servers, and OpenAI-compat third parties).
public struct OpenAICompatAdapter: ProviderAdapter {
    public let baseURL: URL
    public let apiKey: String
    private let session: URLSession

    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.openai.com")!,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
    }

    private func request(path: String, method: String) -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        if !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        return req
    }

    public func stream(_ modelRequest: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = self.request(path: "v1/chat/completions", method: "POST")
                    req.httpBody = try JSONSerialization.data(withJSONObject: Self.buildBody(modelRequest))

                    let bytes = try await ProviderTransport.openSSEStream(session: session, request: req)
                    var acc = SSEAccumulator()
                    var state = CompatStreamState()

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard let frame = acc.feed(line) else { continue }
                        if frame.data == "[DONE]" {
                            Self.finish(state: state, continuation: continuation)
                            continuation.finish()
                            return
                        }
                        Self.handle(frame, state: &state, continuation: continuation)
                    }
                    if let frame = acc.flush(), frame.data != "[DONE]" {
                        Self.handle(frame, state: &state, continuation: continuation)
                    }
                    Self.finish(state: state, continuation: continuation)
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
        state: inout CompatStreamState,
        continuation: AsyncThrowingStream<ModelStreamEvent, Error>.Continuation
    ) {
        guard let data = frame.data.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let usage = obj["usage"] as? [String: Any] {
            state.usage = Usage(
                inputTokens: usage["prompt_tokens"] as? Int ?? 0,
                outputTokens: usage["completion_tokens"] as? Int ?? 0
            )
        }

        guard let choices = obj["choices"] as? [[String: Any]], let choice = choices.first else { return }

        if let delta = choice["delta"] as? [String: Any] {
            if let content = delta["content"] as? String, !content.isEmpty {
                continuation.yield(.textDelta(content))
            }
            if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
                continuation.yield(.thinkingDelta(reasoning))
            }
            if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                for call in toolCalls {
                    let index = call["index"] as? Int ?? 0
                    let function = call["function"] as? [String: Any]
                    if let id = call["id"] as? String, let name = function?["name"] as? String {
                        state.toolIDByIndex[index] = id
                        state.sawToolCall = true
                        continuation.yield(.toolUseStart(id: id, name: name))
                    }
                    if let args = function?["arguments"] as? String, let id = state.toolIDByIndex[index] {
                        continuation.yield(.toolInputDelta(id: id, jsonFragment: args))
                    }
                }
            }
        }

        if let reason = choice["finish_reason"] as? String {
            state.stopReason = mapStop(reason)
            for id in state.toolIDByIndex.values { continuation.yield(.toolUseEnd(id: id)) }
        }
    }

    private static func finish(
        state: CompatStreamState,
        continuation: AsyncThrowingStream<ModelStreamEvent, Error>.Continuation
    ) {
        continuation.yield(.usage(state.usage))
        continuation.yield(.stop(state.stopReason))
    }

    private static func mapStop(_ raw: String) -> StopReason {
        switch raw {
        case "stop": .endTurn
        case "tool_calls", "function_call": .toolUse
        case "length": .maxTokens
        default: .other
        }
    }

    // MARK: - Body

    static func buildBody(_ req: ModelRequest) -> [String: Any] {
        var messages: [[String: Any]] = []
        if let system = req.system, !system.isEmpty {
            messages.append(["role": "system", "content": system])
        }
        messages.append(contentsOf: req.messages.flatMap(messageItems))

        var body: [String: Any] = [
            "model": req.model,
            "stream": true,
            "stream_options": ["include_usage": true],
            "messages": messages,
            "max_tokens": req.maxTokens,
        ]
        if let effort = req.reasoningEffort {
            body["reasoning_effort"] = effort.rawValue
        } else if let temp = req.temperature {
            body["temperature"] = temp
        }
        if !req.tools.isEmpty {
            body["tools"] = req.tools.map { tool in
                [
                    "type": "function",
                    "function": [
                        "name": tool.name,
                        "description": tool.description,
                        "parameters": tool.parameters.anyValue,
                    ],
                ]
            }
        }
        return body
    }

    /// One neutral message can expand into several chat messages (each tool
    /// result is its own role:tool message).
    private static func messageItems(_ message: NeutralMessage) -> [[String: Any]] {
        let role: String = switch message.role {
        case .assistant: "assistant"
        case .system: "system"
        case .tool: "tool"
        case .user: "user"
        }

        // Each tool_result becomes a separate role:tool message; any images ride
        // in a follow-up user message (role:tool content is text-only).
        var toolResults: [[String: Any]] = []
        var resultImages: [ImageSource] = []
        for block in message.content {
            if case .toolResult(let toolUseId, let content, _, let images) = block {
                toolResults.append(["role": "tool", "tool_call_id": toolUseId, "content": content])
                resultImages.append(contentsOf: images)
            }
        }
        if !toolResults.isEmpty {
            if !resultImages.isEmpty {
                let parts: [[String: Any]] = [["type": "text", "text": "Images returned by the tool call(s) above:"]]
                    + resultImages.map { ["type": "image_url", "image_url": ["url": $0.dataURL]] }
                toolResults.append(["role": "user", "content": parts])
            }
            return toolResults
        }

        // Assistant tool calls.
        let toolCalls = message.content.compactMap { block -> [String: Any]? in
            if case .toolUse(let id, let name, let input) = block {
                return ["id": id, "type": "function", "function": ["name": name, "arguments": input.jsonString]]
            }
            return nil
        }
        if !toolCalls.isEmpty {
            return [["role": "assistant", "content": message.plainText, "tool_calls": toolCalls]]
        }

        // Multimodal user content.
        let hasImage = message.content.contains { if case .image = $0 { return true } else { return false } }
        if hasImage {
            let parts = message.content.compactMap { block -> [String: Any]? in
                switch block {
                case .text(let t): return ["type": "text", "text": t]
                case .image(let img): return ["type": "image_url", "image_url": ["url": img.dataURL]]
                default: return nil
                }
            }
            return [["role": role, "content": parts]]
        }

        // Some servers reject messages with empty content.
        guard !message.plainText.isEmpty else { return [] }
        return [["role": role, "content": message.plainText]]
    }

    // MARK: - Models

    public func listModels() async throws -> [ProviderModel] {
        let req = request(path: "v1/models", method: "GET")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return []
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["data"] as? [[String: Any]] else { return [] }
        return models.compactMap { m in
            guard let id = m["id"] as? String else { return nil }
            return ProviderModel(id: id)
        }
    }
}

private struct CompatStreamState {
    var usage = Usage()
    var stopReason: StopReason = .endTurn
    var toolIDByIndex: [Int: String] = [:]
    var sawToolCall = false
}
