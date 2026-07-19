import Foundation

/// OpenAI Responses API adapter. Required (over Chat Completions) because it is
/// the only surface that accepts `reasoning.effort` together with tools.
public struct OpenAIResponsesAdapter: ProviderAdapter {
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
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        return req
    }

    public func stream(_ modelRequest: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = self.request(path: "v1/responses", method: "POST")
                    req.httpBody = try JSONSerialization.data(withJSONObject: Self.buildBody(modelRequest))

                    let bytes = try await ProviderTransport.openSSEStream(session: session, request: req)
                    var acc = SSEAccumulator()
                    var state = ResponsesStreamState()

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
        state: inout ResponsesStreamState,
        continuation: AsyncThrowingStream<ModelStreamEvent, Error>.Continuation
    ) throws {
        guard let data = frame.data.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }

        switch type {
        case "response.output_text.delta":
            if let delta = obj["delta"] as? String { continuation.yield(.textDelta(delta)) }

        case "response.reasoning_summary_text.delta":
            if let delta = obj["delta"] as? String { continuation.yield(.thinkingDelta(delta)) }

        case "response.output_item.added":
            if let item = obj["item"] as? [String: Any], item["type"] as? String == "function_call",
               let itemID = item["id"] as? String,
               let callID = item["call_id"] as? String,
               let name = item["name"] as? String {
                state.callIDByItemID[itemID] = callID
                state.sawToolCall = true
                continuation.yield(.toolUseStart(id: callID, name: name))
            }

        case "response.function_call_arguments.delta":
            if let itemID = obj["item_id"] as? String,
               let callID = state.callIDByItemID[itemID],
               let delta = obj["delta"] as? String {
                continuation.yield(.toolInputDelta(id: callID, jsonFragment: delta))
            }

        case "response.output_item.done":
            if let item = obj["item"] as? [String: Any], item["type"] as? String == "function_call",
               let itemID = item["id"] as? String, let callID = state.callIDByItemID[itemID] {
                continuation.yield(.toolUseEnd(id: callID))
            }

        case "response.completed":
            if let response = obj["response"] as? [String: Any],
               let usage = response["usage"] as? [String: Any] {
                let input = usage["input_tokens"] as? Int ?? 0
                let output = usage["output_tokens"] as? Int ?? 0
                continuation.yield(.usage(Usage(inputTokens: input, outputTokens: output)))
            }
            continuation.yield(.stop(state.sawToolCall ? .toolUse : .endTurn))

        case "response.failed", "error":
            let message = ((obj["response"] as? [String: Any])?["error"] as? [String: Any])?["message"] as? String
                ?? (obj["message"] as? String)
                ?? "unknown error"
            throw ProviderError.stream(message: message)

        default:
            break
        }
    }

    // MARK: - Body

    static func buildBody(_ req: ModelRequest) -> [String: Any] {
        var body: [String: Any] = [
            "model": req.model,
            "stream": true,
            "input": req.messages.flatMap(inputItems),
            "max_output_tokens": max(req.maxTokens, 4096),
        ]
        if let system = req.system, !system.isEmpty {
            body["instructions"] = system
        }
        if let effort = req.reasoningEffort {
            body["reasoning"] = ["effort": effort.rawValue, "summary": "auto"]
        } else if let temp = req.temperature {
            body["temperature"] = temp
        }
        if !req.tools.isEmpty {
            body["tools"] = req.tools.map { tool in
                [
                    "type": "function",
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": tool.parameters.anyValue,
                ]
            }
        }
        return body
    }

    /// One neutral message can expand into several Responses input items
    /// (a text message plus function_call / function_call_output items).
    private static func inputItems(_ message: NeutralMessage) -> [[String: Any]] {
        // Tool results become function_call_output items.
        let toolResults = message.content.compactMap { block -> [String: Any]? in
            if case .toolResult(let id, let content, _, _) = block {
                return ["type": "function_call_output", "call_id": id, "output": content]
            }
            return nil
        }
        if !toolResults.isEmpty { return toolResults }

        switch message.role {
        case .assistant:
            var items: [[String: Any]] = []
            let textParts = message.content.compactMap { block -> [String: Any]? in
                if case .text(let t) = block, !t.isEmpty { return ["type": "output_text", "text": t] }
                return nil
            }
            if !textParts.isEmpty {
                items.append(["type": "message", "role": "assistant", "content": textParts])
            }
            for block in message.content {
                if case .toolUse(let id, let name, let input) = block {
                    items.append([
                        "type": "function_call", "call_id": id, "name": name,
                        "arguments": input.jsonString,
                    ])
                }
            }
            return items
        default:
            let parts = message.content.compactMap { block -> [String: Any]? in
                switch block {
                case .text(let t): return ["type": "input_text", "text": t]
                case .image(let img): return ["type": "input_image", "image_url": img.dataURL]
                default: return nil
                }
            }
            return [["type": "message", "role": "user", "content": parts]]
        }
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

private struct ResponsesStreamState {
    var callIDByItemID: [String: String] = [:]
    var sawToolCall = false
}
