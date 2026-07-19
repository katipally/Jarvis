import AppKit
import JAgent
import JMemory
import JStore
import Observation

/// A message as shown in the notch.
struct DisplayMessage: Identifiable, Equatable {
    enum ToolState: Equatable { case running, done, error }

    let id: String
    var role: MessageRole
    var text: String = ""
    var thinking: String = ""
    var images: [ImageSource] = []
    var isStreaming: Bool = false
    var isError: Bool = false
    var toolName: String? = nil
    var toolState: ToolState? = nil
}

/// A file/image dropped onto the chat, pending send.
struct Attachment: Identifiable, Equatable {
    let id = UUID().uuidString
    let filename: String
    var image: ImageSource?
    var text: String?

    var isImage: Bool { image != nil }
}

/// Drives the active conversation: input, streaming, tool calls, persistence,
/// interruption. Uses the full AgentLoop so tools + approvals work.
@MainActor
@Observable
final class ChatStore {
    enum Phase: Equatable { case idle, responding }

    let core: JarvisCore
    let sessions: SessionManager
    let agent: AgentServices
    /// Set after construction; injects recalled memory into each turn's system prompt.
    var memory: MemoryService?
    var graphReader: GraphReader?

    var messages: [DisplayMessage] = []
    var attachments: [Attachment] = []
    var input: String = ""
    var phase: Phase = .idle
    var errorText: String?

    /// Fired once when a run finishes (used by voice to pulse "answer ready").
    var onRunComplete: (@MainActor () -> Void)?

    /// Set when Jarvis proactively sends something the user hasn't seen — glows the notch.
    var hasUnreadProactive = false

    private var transcript: [NeutralMessage] = []
    private var pendingToolResults: [ContentBlock] = []
    private var activeAssistantID: String?
    private var runTask: Task<Void, Never>?

    private static let systemPrompt = """
    You are Jarvis, a proactive macOS assistant living in the notch. Be concise and \
    direct. Use Markdown when it aids clarity. You have tools to inspect and act on the \
    Mac — use them when they help, and explain what you did. If you don't know something, \
    say so.
    """

    init(core: JarvisCore, sessions: SessionManager, agent: AgentServices) {
        self.core = core
        self.sessions = sessions
        self.agent = agent
    }

    var canSend: Bool {
        phase == .idle && (!input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
    }

    func send() {
        guard canSend else { return }
        guard let resolved = core.resolve(.brain) else {
            errorText = "Choose a Brain model in Settings first."
            return
        }

        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = attachments.compactMap(\.image)
        let textAttachments = attachments.compactMap(\.text)
        var userText = trimmed
        if !textAttachments.isEmpty {
            let joined = textAttachments.enumerated()
                .map { "--- attached file \($0.offset + 1) ---\n\($0.element)" }
                .joined(separator: "\n\n")
            userText = trimmed.isEmpty ? joined : "\(trimmed)\n\n\(joined)"
        }

        let userMessage = NeutralMessage.user(userText, images: images)
        transcript.append(userMessage)
        messages.append(DisplayMessage(id: UUID().uuidString, role: .user, text: trimmed, images: images))

        input = ""
        attachments = []
        errorText = nil
        phase = .responding
        activeAssistantID = nil
        pendingToolResults = []

        let runID = UUID().uuidString
        let artifactStore = agent.artifactStore
        let tools = agent.tools
        let gate = agent.gate
        let initial = transcript
        let runStore = agent.runStore
        let sessions = self.sessions
        let memory = self.memory
        let adapter = resolved.adapter
        let effort = resolved.effort
        let model = resolved.model
        let providerLabel = resolved.account.provider
        let retrievalQuery = userText
        var usage = Usage()

        runTask = Task { [weak self] in
            await runStore.createRun(id: runID, kind: "foreground", segmentID: nil, initiator: "user")
            _ = try? await sessions.beginUserTurn()
            _ = try? await sessions.append(role: .user, content: userMessage.content, status: .complete)

            // Inject recalled memory into this turn's system prompt.
            let memoryContext = await memory?.context(for: retrievalQuery)
            let system = memoryContext.map { "\(Self.systemPrompt)\n\n\($0)" } ?? Self.systemPrompt
            let loop = AgentLoop(
                adapter: adapter, tools: tools, gate: gate,
                config: .init(model: model, system: system, effort: effort, maxTokens: 4096, maxTurns: 12),
                spill: { name, content in await artifactStore.spill(runID: runID, toolName: name, content: content) }
            )

            for await event in loop.run(initial: initial, runID: runID) {
                guard let self else { break }
                switch event {
                case .runStarted:
                    break
                case .textDelta(let t):
                    self.appendToAssistant(t, thinking: false)
                case .thinkingDelta(let t):
                    self.appendToAssistant(t, thinking: true)
                case .assistantMessage(let m):
                    self.flushPendingToolResults()
                    self.finalizeAssistant(m)
                    self.transcript.append(m)
                    if !m.plainText.isEmpty {
                        _ = try? await sessions.append(role: .assistant, content: m.content, status: .complete,
                                                       runId: runID, model: model, provider: providerLabel)
                    }
                case .toolCallStarted(let id, let name, let input):
                    self.messages.append(DisplayMessage(id: id, role: .tool, toolName: name, toolState: .running))
                    await runStore.toolStarted(id: id, runID: runID, name: name, input: input)
                case .toolCallFinished(let id, let output, let isError):
                    self.updateToolRow(id: id, output: output, isError: isError)
                    self.pendingToolResults.append(.toolResult(toolUseId: id, content: output, isError: isError, images: []))
                    await runStore.toolFinished(id: id, state: isError ? "error" : "done", preview: output)
                case .usage(let u):
                    usage.inputTokens += u.inputTokens
                    usage.outputTokens += u.outputTokens
                case .completed:
                    self.flushPendingToolResults()
                case .aborted:
                    self.repairDanglingTools()
                    self.markActiveAborted()
                case .failed(let message):
                    self.showFailure(message)
                }
            }

            let status = self?.errorText == nil ? "done" : "error"
            await runStore.finishRun(id: runID, status: status, usage: usage, error: self?.errorText)
            await MainActor.run {
                self?.phase = .idle
                self?.onRunComplete?()
            }
        }
    }

    func interrupt() {
        runTask?.cancel()
    }

    func addAttachment(_ attachment: Attachment) { attachments.append(attachment) }
    func removeAttachment(_ id: String) { attachments.removeAll { $0.id == id } }

    /// Jarvis-initiated message (nudge, cron brief, heartbeat). Appears in chat + glows the notch.
    func receiveProactive(_ body: String) {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append(DisplayMessage(id: UUID().uuidString, role: .assistant, text: text))
        transcript.append(.assistant(text))
        hasUnreadProactive = true
    }

    func markProactiveRead() { hasUnreadProactive = false }

    var latestAssistant: DisplayMessage? {
        messages.last { $0.role == .assistant }
    }

    // MARK: - Event handling helpers

    private func appendToAssistant(_ text: String, thinking: Bool) {
        if activeAssistantID == nil {
            let id = UUID().uuidString
            messages.append(DisplayMessage(id: id, role: .assistant, isStreaming: true))
            activeAssistantID = id
        }
        mutate(activeAssistantID!) { thinking ? ($0.thinking += text) : ($0.text += text) }
    }

    private func finalizeAssistant(_ message: NeutralMessage) {
        if let id = activeAssistantID {
            mutate(id) { $0.text = message.plainText; $0.isStreaming = false }
            activeAssistantID = nil
        } else if !message.plainText.isEmpty {
            messages.append(DisplayMessage(id: UUID().uuidString, role: .assistant, text: message.plainText))
        }
    }

    private func updateToolRow(id: String, output: String, isError: Bool) {
        mutate(id) { $0.toolState = isError ? .error : .done; $0.text = output }
    }

    private func flushPendingToolResults() {
        guard !pendingToolResults.isEmpty else { return }
        transcript.append(NeutralMessage(role: .user, content: pendingToolResults))
        pendingToolResults = []
    }

    /// After an abort, synthesize results for any tool_use left without one so
    /// the next model call sees a valid transcript.
    private func repairDanglingTools() {
        if let last = transcript.last, last.role == .assistant {
            let toolIDs = last.content.compactMap { block -> String? in
                if case .toolUse(let id, _, _) = block { return id }
                return nil
            }
            let resolved = Set(pendingToolResults.compactMap { block -> String? in
                if case .toolResult(let id, _, _, _) = block { return id }
                return nil
            })
            for id in toolIDs where !resolved.contains(id) {
                pendingToolResults.append(.toolResult(toolUseId: id, content: "Cancelled by the user.", isError: true, images: []))
            }
        }
        flushPendingToolResults()
    }

    private func markActiveAborted() {
        if let id = activeAssistantID {
            mutate(id) {
                $0.isStreaming = false
                if $0.text.isEmpty { $0.text = "_(cancelled)_" }
            }
            activeAssistantID = nil
        }
    }

    private func showFailure(_ message: String) {
        if let id = activeAssistantID {
            mutate(id) { $0.isStreaming = false; $0.isError = true; $0.text = message }
            activeAssistantID = nil
        } else {
            messages.append(DisplayMessage(id: UUID().uuidString, role: .assistant, text: message, isError: true))
        }
        errorText = message
    }

    private func mutate(_ id: String, _ change: (inout DisplayMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        change(&messages[index])
    }
}
