import Foundation
import Testing
@testable import JAgent

/// Emits a scripted sequence of provider events.
struct FakeAdapter: ProviderAdapter {
    let events: [ModelStreamEvent]
    var throwAfter: Int? = nil

    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var i = 0
                for event in events {
                    try Task.checkCancellation()
                    continuation.yield(event)
                    i += 1
                    if let throwAfter, i == throwAfter {
                        continuation.finish(throwing: ProviderError.stream(message: "boom"))
                        return
                    }
                    try await Task.sleep(for: .milliseconds(1))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func listModels() async throws -> [ProviderModel] { [] }
}

@Test func chatEngineStreamsTextAndCompletes() async {
    let adapter = FakeAdapter(events: [
        .textDelta("Hel"), .textDelta("lo"),
        .usage(Usage(inputTokens: 5, outputTokens: 2)),
        .stop(.endTurn),
    ])
    let engine = ChatEngine(adapter: adapter)

    var deltas = ""
    var final: NeutralMessage?
    var completed: StopReason?
    for await event in engine.run(ModelRequest(model: "x", messages: [.user("hi")])) {
        switch event {
        case .textDelta(let t): deltas += t
        case .assistantMessage(let m): final = m
        case .completed(let r): completed = r
        default: break
        }
    }
    #expect(deltas == "Hello")
    #expect(final?.plainText == "Hello")
    #expect(completed == .endTurn)
}

@Test func chatEngineSurfacesProviderError() async {
    let adapter = FakeAdapter(events: [.textDelta("partial")], throwAfter: 1)
    let engine = ChatEngine(adapter: adapter)

    var failed: String?
    for await event in engine.run(ModelRequest(model: "x", messages: [.user("hi")])) {
        if case .failed(let m) = event { failed = m }
    }
    #expect(failed != nil)
}

@Test func messageAssemblerBuildsToolUse() {
    var a = MessageAssembler()
    a.appendText("calling")
    a.startTool(id: "t1", name: "open_url")
    a.appendToolInput(id: "t1", fragment: #"{"url":"#)
    a.appendToolInput(id: "t1", fragment: #""https://x"}"#)
    a.endTool(id: "t1")
    let msg = a.message()
    #expect(msg.plainText == "calling")
    let hasTool = msg.content.contains {
        if case .toolUse(_, let name, _) = $0 { return name == "open_url" }
        return false
    }
    #expect(hasTool)
}

@Test func anthropicBodyUsesAdaptiveThinkingOnCurrentModels() {
    let req = ModelRequest(model: "claude-opus-4-8", messages: [.user("hi")], maxTokens: 1000, reasoningEffort: .medium)
    let body = AnthropicAdapter.buildBody(req, firstParty: true)
    let thinking = body["thinking"] as? [String: Any]
    #expect(thinking?["type"] as? String == "adaptive")
    #expect(thinking?["budget_tokens"] == nil) // rejected with 400 on current models
    let outputConfig = body["output_config"] as? [String: Any]
    #expect(outputConfig?["effort"] as? String == "medium")
    #expect((body["max_tokens"] as? Int ?? 0) >= 16_000) // thinking shares the budget
    #expect(body["temperature"] == nil)
    #expect((body["cache_control"] as? [String: Any])?["type"] as? String == "ephemeral")
}

@Test func anthropicBodyKeepsLegacyThinkingForCompatEndpoints() {
    let req = ModelRequest(model: "MiniMax-M2", messages: [.user("hi")], maxTokens: 1000, reasoningEffort: .medium)
    let body = AnthropicAdapter.buildBody(req, firstParty: false)
    let thinking = body["thinking"] as? [String: Any]
    #expect(thinking?["type"] as? String == "enabled")
    #expect((body["max_tokens"] as? Int ?? 0) > (thinking?["budget_tokens"] as? Int ?? 0))
    #expect(body["cache_control"] == nil) // first-party-only field
}

@Test func anthropicReplaysSignedThinkingAndDropsUnsigned() {
    let messages: [NeutralMessage] = [
        .user("hi"),
        NeutralMessage(role: .assistant, content: [
            .thinking("signed reasoning", signature: "sigABC"),
            .thinking("unsigned reasoning", signature: nil),
            .thinking("foreign reasoning", signature: #"{"type":"reasoning"}"#),
            .toolUse(id: "t1", name: "list_apps", input: .object([:])),
        ]),
        NeutralMessage(role: .user, content: [.toolResult(toolUseId: "t1", content: "ok", isError: false, images: [])]),
    ]
    let body = AnthropicAdapter.buildBody(ModelRequest(model: "claude-opus-4-8", messages: messages), firstParty: true)
    let wire = body["messages"] as? [[String: Any]]
    let assistant = wire?[1]["content"] as? [[String: Any]]
    let thinkingBlocks = assistant?.filter { $0["type"] as? String == "thinking" }
    #expect(thinkingBlocks?.count == 1) // only the natively signed block survives
    #expect(thinkingBlocks?.first?["signature"] as? String == "sigABC")
    // Signed thinking must precede its tool_use.
    #expect(assistant?.last?["type"] as? String == "tool_use")
}

@Test func anthropicDropsEmptyMessagesAndEmptyTextBlocks() {
    let messages: [NeutralMessage] = [
        .user("hi"),
        NeutralMessage(role: .assistant, content: [.text("")]), // empty turn must not reach the wire
    ]
    let body = AnthropicAdapter.buildBody(ModelRequest(model: "claude-opus-4-8", messages: messages), firstParty: true)
    let wire = body["messages"] as? [[String: Any]]
    #expect(wire?.count == 1)
}

@Test func assemblerPreservesInterleavedOrderAndSignature() {
    var a = MessageAssembler()
    a.appendThinking("think first")
    a.attachThinkingSignature("sig1")
    a.appendText("then speak")
    a.startTool(id: "t1", name: "x")
    a.appendToolInput(id: "t1", fragment: "{}")
    a.endTool(id: "t1")
    let msg = a.message()
    guard msg.content.count == 3,
          case .thinking(let t, let sig) = msg.content[0],
          case .text(let text) = msg.content[1],
          case .toolUse = msg.content[2]
    else {
        Issue.record("unexpected block layout: \(msg.content)")
        return
    }
    #expect(t == "think first")
    #expect(sig == "sig1")
    #expect(text == "then speak")
}

@Test func assemblerFlagsMalformedToolInput() {
    var a = MessageAssembler()
    a.startTool(id: "t1", name: "x")
    a.appendToolInput(id: "t1", fragment: #"{"truncated": "#) // cut off mid-JSON
    _ = a.message()
    #expect(a.malformedToolIDs.contains("t1"))
}

@Test func responsesBodyUsesReasoningEffort() {
    let req = ModelRequest(model: "gpt-5.5", messages: [.user("hi")], reasoningEffort: .high)
    let body = OpenAIResponsesAdapter.buildBody(req)
    let reasoning = body["reasoning"] as? [String: Any]
    #expect(reasoning?["effort"] as? String == "high")
    #expect(body["input"] != nil)
}

@Test func compatBodyIncludesUsageOption() {
    let req = ModelRequest(model: "m", system: "sys", messages: [.user("hi")])
    let body = OpenAICompatAdapter.buildBody(req)
    let messages = body["messages"] as? [[String: Any]]
    #expect(messages?.first?["role"] as? String == "system")
    #expect((body["stream_options"] as? [String: Any])?["include_usage"] as? Bool == true)
}

@Test func jsonValueRoundTrips() {
    let original = JSONValue.object(["a": .number(1), "b": .array([.string("x"), .bool(true)])])
    let string = original.jsonString
    let parsed = JSONValue.parse(string)
    #expect(parsed == original)
}

/// Regression: SSE frames are delimited by EMPTY lines, which
/// URLSession.AsyncBytes.lines silently drops. The custom splitter must
/// preserve them or no frame ever completes mid-stream.
@Test func sseLineSplitterPreservesEmptyLines() async throws {
    let wire = "event: content_block_delta\r\ndata: {\"a\":1}\r\n\r\nevent: message_stop\ndata: {}\n\n"
    let bytes = AsyncStream<UInt8> { continuation in
        for byte in Array(wire.utf8) { continuation.yield(byte) }
        continuation.finish()
    }
    var lines: [String] = []
    for try await line in ProviderTransport.sseLines(bytes) {
        lines.append(line)
    }
    #expect(lines == [
        "event: content_block_delta", "data: {\"a\":1}", "",
        "event: message_stop", "data: {}", "",
    ])

    // And the accumulator turns them into two complete frames.
    var acc = SSEAccumulator()
    let frames = lines.compactMap { acc.feed($0) }
    #expect(frames.count == 2)
    #expect(frames.first?.data == "{\"a\":1}")
}
