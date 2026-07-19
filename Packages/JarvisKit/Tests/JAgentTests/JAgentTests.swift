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

@Test func anthropicBodyEnablesThinkingForEffort() {
    let req = ModelRequest(model: "claude", messages: [.user("hi")], maxTokens: 1000, reasoningEffort: .medium)
    let body = AnthropicAdapter.buildBody(req)
    let thinking = body["thinking"] as? [String: Any]
    #expect(thinking?["type"] as? String == "enabled")
    // max_tokens must exceed the thinking budget.
    #expect((body["max_tokens"] as? Int ?? 0) > (thinking?["budget_tokens"] as? Int ?? 0))
    #expect(body["temperature"] == nil)
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
