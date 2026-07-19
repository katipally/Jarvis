import Foundation

/// The full agentic loop: stream a turn, run any tool calls (through the approval
/// gate) serially, feed results back, repeat until the model stops or the turn
/// cap is hit. Cancellation persists a clean, tool-repaired transcript.
public struct AgentLoop: Sendable {
    public struct Config: Sendable {
        public var model: String
        public var system: String?
        public var effort: ReasoningEffort?
        public var maxTokens: Int
        public var maxTurns: Int
        public var isBackground: Bool

        public init(model: String, system: String? = nil, effort: ReasoningEffort? = nil,
                    maxTokens: Int = 4096, maxTurns: Int = 12, isBackground: Bool = false) {
            self.model = model
            self.system = system
            self.effort = effort
            self.maxTokens = maxTokens
            self.maxTurns = maxTurns
            self.isBackground = isBackground
        }
    }

    /// Per-result cap before overflow is spilled to an artifact.
    public static let spillThreshold = 16_000

    let adapter: any ProviderAdapter
    let tools: ToolRegistry
    let gate: ApprovalGate
    let config: Config
    let transform: (@Sendable ([NeutralMessage]) async -> [NeutralMessage])?
    let steering: (@Sendable () async -> [NeutralMessage])?
    let spill: (@Sendable (_ toolName: String, _ content: String) async -> String)?

    public init(
        adapter: any ProviderAdapter,
        tools: ToolRegistry,
        gate: ApprovalGate,
        config: Config,
        transform: (@Sendable ([NeutralMessage]) async -> [NeutralMessage])? = nil,
        steering: (@Sendable () async -> [NeutralMessage])? = nil,
        spill: (@Sendable (_ toolName: String, _ content: String) async -> String)? = nil
    ) {
        // Background runs can only ever see read-only tools.
        self.adapter = adapter
        self.tools = config.isBackground ? tools.readOnlyOnly() : tools
        self.gate = gate
        self.config = config
        self.transform = transform
        self.steering = steering
        self.spill = spill
    }

    public func run(initial: [NeutralMessage], runID: String) -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            let task = Task {
                continuation.yield(.runStarted)
                var messages = initial
                var lastAssistantText = ""
                var turn = 0

                do {
                    while turn < config.maxTurns {
                        try Task.checkCancellation()

                        if let steering {
                            let extra = await steering()
                            if !extra.isEmpty { messages.append(contentsOf: extra) }
                        }

                        var contextMessages = messages
                        if let transform { contextMessages = await transform(messages) }

                        let request = ModelRequest(
                            model: config.model,
                            system: config.system,
                            messages: contextMessages,
                            tools: tools.schemas,
                            maxTokens: config.maxTokens,
                            reasoningEffort: config.effort
                        )

                        var assembler = MessageAssembler()
                        var stop: StopReason = .endTurn
                        for try await event in adapter.stream(request) {
                            try Task.checkCancellation()
                            switch event {
                            case .textDelta(let t): assembler.appendText(t); continuation.yield(.textDelta(t))
                            case .thinkingDelta(let t): assembler.appendThinking(t); continuation.yield(.thinkingDelta(t))
                            case .toolUseStart(let id, let name): assembler.startTool(id: id, name: name)
                            case .toolInputDelta(let id, let frag): assembler.appendToolInput(id: id, fragment: frag)
                            case .toolUseEnd(let id): assembler.endTool(id: id)
                            case .usage(let u): continuation.yield(.usage(u))
                            case .stop(let r): stop = r
                            }
                        }

                        let assistant = assembler.message()
                        if !assistant.plainText.isEmpty { lastAssistantText = assistant.plainText }
                        messages.append(assistant)
                        continuation.yield(.assistantMessage(assistant))

                        let toolUses: [(id: String, name: String, input: JSONValue)] = assistant.content.compactMap {
                            if case .toolUse(let id, let name, let input) = $0 { return (id, name, input) }
                            return nil
                        }
                        if toolUses.isEmpty {
                            continuation.yield(.completed(stop))
                            continuation.finish()
                            return
                        }

                        var resultBlocks: [ContentBlock] = []
                        for use in toolUses {
                            try Task.checkCancellation()
                            let tool = tools.tool(named: use.name)
                            let scope = tool?.scopeKey?(use.input)
                            let summary = tool?.summarize?(use.input) ?? use.name
                            continuation.yield(.toolCallStarted(id: use.id, name: use.name, input: use.input))

                            let request = ApprovalRequest(
                                runID: runID, toolCallID: use.id, toolName: use.name,
                                scopeKey: scope, summary: summary, input: use.input
                            )
                            let (decision, _) = await withTaskCancellationHandler {
                                await gate.decide(request, tier: tool?.tier ?? .externalEffect, isBackground: config.isBackground)
                            } onCancel: {
                                let gate = gate
                                let id = request.id
                                Task { await gate.cancel(id) }
                            }

                            var output: ToolOutput
                            if case .deny = decision {
                                output = ToolOutput("Denied by the user.", isError: true)
                            } else if let tool {
                                do {
                                    let ctx = ToolContext(runID: runID, isBackground: config.isBackground)
                                    output = try await tool.run(use.input, ctx)
                                } catch is CancellationError {
                                    throw CancellationError()
                                } catch {
                                    output = ToolOutput("Tool error: \(error.localizedDescription)", isError: true)
                                }
                            } else {
                                output = ToolOutput("Unknown tool: \(use.name)", isError: true)
                            }

                            var content = output.content
                            if content.count > Self.spillThreshold, let spill {
                                let ref = await spill(use.name, content)
                                content = String(content.prefix(2000)) +
                                    "\n\n…[output truncated; full result saved as \(ref). Use read_artifact to read it.]"
                            }
                            continuation.yield(.toolCallFinished(id: use.id, output: content, isError: output.isError))
                            resultBlocks.append(.toolResult(toolUseId: use.id, content: content, isError: output.isError, images: output.images))
                        }

                        messages.append(NeutralMessage(role: .user, content: resultBlocks))
                        turn += 1
                    }

                    // Turn cap hit: fall back to the last non-empty assistant text.
                    if !lastAssistantText.isEmpty {
                        continuation.yield(.assistantMessage(.assistant(lastAssistantText)))
                    }
                    continuation.yield(.completed(.maxTokens))
                    continuation.finish()
                } catch is CancellationError {
                    await gate.cancelAll()
                    continuation.yield(.aborted)
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(error.localizedDescription))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
