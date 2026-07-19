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

    /// True for api.anthropic.com — gates first-party-only request fields
    /// (adaptive thinking, output_config, cache_control) that compatible
    /// endpoints like MiniMax may not accept.
    var isFirstParty: Bool {
        baseURL.host?.hasSuffix("anthropic.com") ?? false
    }

    public func stream(_ modelRequest: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = self.request(path: "v1/messages", method: "POST")
                    let body = Self.buildBody(modelRequest, firstParty: self.isFirstParty)
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let bytes = try await ProviderTransport.openSSEStream(session: session, request: req)
                    var acc = SSEAccumulator()
                    var state = AnthropicStreamState()
                    let debugLog = SSEDebugLog() // no-op unless JARVIS_SSE_LOG is set

                    for try await line in ProviderTransport.sseLines(bytes) {
                        try Task.checkCancellation()
                        debugLog.write(line)
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
                // Cache reads/writes bill at different rates — keep them apart;
                // Usage.promptTokens re-folds them for context budgets.
                state.inputTokens = usage["input_tokens"] as? Int ?? 0
                state.cacheReadTokens = usage["cache_read_input_tokens"] as? Int ?? 0
                state.cacheWriteTokens = usage["cache_creation_input_tokens"] as? Int ?? 0
            }

        case "content_block_start":
            let index = obj["index"] as? Int ?? 0
            if let block = obj["content_block"] as? [String: Any],
               let blockType = block["type"] as? String {
                if blockType == "tool_use", let id = block["id"] as? String, let name = block["name"] as? String {
                    state.toolIDByIndex[index] = id
                    continuation.yield(.toolUseStart(id: id, name: name))
                } else if blockType == "thinking" {
                    state.thinkingIndexes.insert(index)
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
                case "signature_delta":
                    if let sig = delta["signature"] as? String {
                        state.signatureByIndex[index, default: ""] += sig
                    }
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
            if state.thinkingIndexes.contains(index), let sig = state.signatureByIndex[index], !sig.isEmpty {
                continuation.yield(.thinkingSignature(sig))
            }

        case "message_delta":
            if let delta = obj["delta"] as? [String: Any], let reason = delta["stop_reason"] as? String {
                state.stopReason = mapStop(reason)
            }
            if let usage = obj["usage"] as? [String: Any] {
                state.outputTokens = usage["output_tokens"] as? Int ?? state.outputTokens
            }

        case "message_stop":
            continuation.yield(.usage(Usage(
                inputTokens: state.inputTokens, outputTokens: state.outputTokens,
                cacheReadTokens: state.cacheReadTokens, cacheWriteTokens: state.cacheWriteTokens
            )))
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

    /// Models that accept `thinking: {type: "adaptive"}` + `output_config.effort`.
    /// Older families (Sonnet/Opus ≤4.5, Haiku) still need the legacy
    /// `budget_tokens` shape.
    static func supportsAdaptiveThinking(_ model: String) -> Bool {
        if model.contains("fable") || model.contains("mythos") { return true }
        if model.contains("sonnet-5") || model.contains("opus-5") { return true }
        for family in ["opus-4-", "sonnet-4-"] {
            if let range = model.range(of: family),
               let minor = Int(model[range.upperBound...].prefix(1)), minor >= 6 {
                return true
            }
        }
        return false
    }

    static func buildBody(_ req: ModelRequest, firstParty: Bool) -> [String: Any] {
        var body: [String: Any] = [
            "model": req.model,
            "stream": true,
            "messages": req.messages.compactMap(messageJSON),
        ]

        var maxTokens = req.maxTokens
        if let effort = req.reasoningEffort {
            if firstParty && supportsAdaptiveThinking(req.model) {
                body["thinking"] = ["type": "adaptive"]
                body["output_config"] = ["effort": effort.anthropicEffort]
                maxTokens = max(maxTokens, 16_000) // thinking counts against max_tokens
            } else {
                let budget = effort.anthropicBudget
                maxTokens = max(maxTokens, budget + 4096)
                body["thinking"] = ["type": "enabled", "budget_tokens": budget]
            }
        } else if let temp = req.temperature {
            body["temperature"] = temp
        }
        body["max_tokens"] = maxTokens

        if firstParty {
            // Auto-place a cache breakpoint on the last cacheable block so the
            // whole prefix (tools + system + history) is reused across turns.
            body["cache_control"] = ["type": "ephemeral"]
        }
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

    private static func messageJSON(_ message: NeutralMessage) -> [String: Any]? {
        // Anthropic has only user/assistant roles; tool results ride inside a user turn.
        let role = (message.role == .assistant) ? "assistant" : "user"
        let blocks = message.content.compactMap(blockJSON)
        guard !blocks.isEmpty else { return nil } // empty content blocks are rejected by the API
        return ["role": role, "content": blocks]
    }

    private static func blockJSON(_ block: ContentBlock) -> [String: Any]? {
        switch block {
        case .text(let t):
            return t.isEmpty ? nil : ["type": "text", "text": t]
        case .thinking(let t, let signature):
            // Replay only signed thinking (required before tool_use on current
            // models). Signatures starting with "{" belong to other providers.
            guard let signature, !signature.isEmpty, !signature.hasPrefix("{") else { return nil }
            return ["type": "thinking", "thinking": t, "signature": signature]
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
        if var components = URLComponents(url: req.url!, resolvingAgainstBaseURL: false) {
            components.queryItems = [URLQueryItem(name: "limit", value: "100")]
            req.url = components.url
        }
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
    var cacheReadTokens = 0
    var cacheWriteTokens = 0
    var stopReason: StopReason = .endTurn
    var toolIDByIndex: [Int: String] = [:]
    var thinkingIndexes: Set<Int> = []
    var signatureByIndex: [Int: String] = [:]
}

/// Raw-wire diagnostics: appends every SSE line to the file named by the
/// JARVIS_SSE_LOG environment variable. Inert in normal runs.
final class SSEDebugLog: @unchecked Sendable {
    private let handle: FileHandle?
    private let lock = NSLock()

    init() {
        guard let path = ProcessInfo.processInfo.environment["JARVIS_SSE_LOG"] else {
            handle = nil
            return
        }
        FileManager.default.createFile(atPath: path, contents: nil)
        handle = FileHandle(forWritingAtPath: path)
        _ = try? handle?.seekToEnd()
    }

    func write(_ line: String) {
        guard let handle else { return }
        lock.withLock {
            try? handle.write(contentsOf: Data((line + "\n").utf8))
        }
    }

    deinit { try? handle?.close() }
}
