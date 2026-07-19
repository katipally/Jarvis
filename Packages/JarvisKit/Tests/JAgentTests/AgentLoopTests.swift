import Foundation
import Testing
@testable import JAgent

/// Returns a different scripted event sequence on each `stream` call (one per turn).
final class ScriptedAdapter: ProviderAdapter, @unchecked Sendable {
    private let turns: [[ModelStreamEvent]]
    private let counter = Counter()

    actor Counter {
        var i = 0
        func next() -> Int { defer { i += 1 }; return i }
    }

    init(_ turns: [[ModelStreamEvent]]) { self.turns = turns }

    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let turns = self.turns
            let counter = self.counter
            let task = Task {
                let idx = await counter.next()
                let events = idx < turns.count ? turns[idx] : [.stop(.endTurn)]
                for event in events {
                    try Task.checkCancellation()
                    continuation.yield(event)
                    try await Task.sleep(for: .milliseconds(1))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func listModels() async throws -> [ProviderModel] { [] }
}

/// Rule store that always asks (no persisted rules) and records events.
actor RecordingRuleStore: ApprovalRuleStore {
    private(set) var logged: [(tool: String, allowed: Bool, by: ApprovalDecider)] = []
    private(set) var remembered: [(tool: String, allow: Bool)] = []
    var ruleAnswer: Bool?

    init(ruleAnswer: Bool? = nil) { self.ruleAnswer = ruleAnswer }

    func matchRule(tool: String, scopeKey: String?) async -> Bool? { ruleAnswer }
    func rememberRule(tool: String, scopeKey: String?, allow: Bool) async { remembered.append((tool, allow)) }
    func logDecision(request: ApprovalRequest, allowed: Bool, by: ApprovalDecider) async { logged.append((request.toolName, allowed, by)) }
    func events() -> [(tool: String, allowed: Bool, by: ApprovalDecider)] { logged }
}

private func echoTool(tier: RiskTier) -> ToolSpec {
    ToolSpec(
        name: "echo", description: "echoes back",
        parameters: .object(["type": .string("object")]),
        tier: tier
    ) { input, _ in
        ToolOutput("echoed: \(input.jsonString)")
    }
}

private func toolCallTurn(id: String, name: String, argsJSON: String) -> [ModelStreamEvent] {
    [.toolUseStart(id: id, name: name), .toolInputDelta(id: id, jsonFragment: argsJSON),
     .toolUseEnd(id: id), .usage(Usage(inputTokens: 3, outputTokens: 3)), .stop(.toolUse)]
}

@Test func loopRunsReadOnlyToolThenAnswers() async {
    let adapter = ScriptedAdapter([
        toolCallTurn(id: "t1", name: "echo", argsJSON: #"{"x":1}"#),
        [.textDelta("all done"), .usage(Usage(inputTokens: 2, outputTokens: 2)), .stop(.endTurn)],
    ])
    let store = RecordingRuleStore()
    let gate = ApprovalGate(store: store) { _ in }
    let loop = AgentLoop(
        adapter: adapter,
        tools: ToolRegistry([echoTool(tier: .readOnly)]),
        gate: gate,
        config: .init(model: "m", maxTurns: 5)
    )

    var toolFinished = false
    var finalText = ""
    for await event in loop.run(initial: [.user("hi")], runID: "r1") {
        switch event {
        case .toolCallFinished(_, let out, let isErr): toolFinished = out.contains("echoed") && !isErr
        case .assistantMessage(let m) where !m.plainText.isEmpty: finalText = m.plainText
        default: break
        }
    }
    #expect(toolFinished)
    #expect(finalText == "all done")
    let logged = await store.events()
    #expect(logged.contains { $0.by == .tierAuto } == false) // readOnly doesn't log; tierAuto is silent
}

@Test func loopDeniesExternalToolInBackground() async {
    let adapter = ScriptedAdapter([
        toolCallTurn(id: "t1", name: "echo", argsJSON: "{}"),
        [.textDelta("ok"), .stop(.endTurn)],
    ])
    let store = RecordingRuleStore()
    let gate = ApprovalGate(store: store) { _ in }
    let loop = AgentLoop(
        adapter: adapter,
        tools: ToolRegistry([echoTool(tier: .externalEffect)]),
        gate: gate,
        config: .init(model: "m", maxTurns: 5, isBackground: true)
    )

    var deniedOrUnknown = false
    for await event in loop.run(initial: [.user("hi")], runID: "r1") {
        if case .toolCallFinished(_, let out, let isErr) = event {
            // Background strips external tools from the registry, so it's unknown; either way it fails closed.
            deniedOrUnknown = isErr && (out.contains("Denied") || out.contains("Unknown"))
        }
    }
    #expect(deniedOrUnknown)
}

@Test func loopHonorsDenyRuleFailClosed() async {
    let adapter = ScriptedAdapter([
        toolCallTurn(id: "t1", name: "echo", argsJSON: "{}"),
        [.textDelta("done"), .stop(.endTurn)],
    ])
    let store = RecordingRuleStore(ruleAnswer: false) // rule says deny
    let gate = ApprovalGate(store: store) { _ in }
    let loop = AgentLoop(
        adapter: adapter,
        tools: ToolRegistry([echoTool(tier: .externalEffect)]),
        gate: gate,
        config: .init(model: "m", maxTurns: 5)
    )

    var denied = false
    for await event in loop.run(initial: [.user("hi")], runID: "r1") {
        if case .toolCallFinished(_, let out, let isErr) = event { denied = isErr && out.contains("Denied") }
    }
    #expect(denied)
    let logged = await store.events()
    #expect(logged.contains { $0.by == .rule && !$0.allowed })
}

@Test func loopTimeoutFailsClosed() async {
    let adapter = ScriptedAdapter([
        toolCallTurn(id: "t1", name: "echo", argsJSON: "{}"),
        [.textDelta("done"), .stop(.endTurn)],
    ])
    let store = RecordingRuleStore() // no rule → parks → times out
    let gate = ApprovalGate(store: store, timeout: .milliseconds(80)) { _ in /* never resolve */ }
    let loop = AgentLoop(
        adapter: adapter,
        tools: ToolRegistry([echoTool(tier: .externalEffect)]),
        gate: gate,
        config: .init(model: "m", maxTurns: 5)
    )

    var denied = false
    for await event in loop.run(initial: [.user("hi")], runID: "r1") {
        if case .toolCallFinished(_, let out, let isErr) = event { denied = isErr && out.contains("Denied") }
    }
    #expect(denied)
    let logged = await store.events()
    #expect(logged.contains { $0.by == .timeout })
}

@Test func loopApprovesViaPresenter() async {
    let adapter = ScriptedAdapter([
        toolCallTurn(id: "t1", name: "echo", argsJSON: "{}"),
        [.textDelta("done"), .stop(.endTurn)],
    ])
    let store = RecordingRuleStore()
    // Presenter resolves the request with allow after it parks.
    nonisolated(unsafe) var gateRef: ApprovalGate?
    let gate = ApprovalGate(store: store) { request in
        let g = gateRef
        Task { await g?.resolve(request.id, .allow(persist: true)) }
    }
    gateRef = gate
    let loop = AgentLoop(
        adapter: adapter,
        tools: ToolRegistry([echoTool(tier: .externalEffect)]),
        gate: gate,
        config: .init(model: "m", maxTurns: 5)
    )

    var echoed = false
    for await event in loop.run(initial: [.user("hi")], runID: "r1") {
        if case .toolCallFinished(_, let out, let isErr) = event { echoed = !isErr && out.contains("echoed") }
    }
    #expect(echoed)
    let remembered = await store.remembered
    #expect(remembered.contains { $0.tool == "echo" && $0.allow })
}
