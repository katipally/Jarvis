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

extension DisplayMessage {
    /// Persisted rows → display rows. Tool activity is reconstructed by pairing
    /// toolUse blocks with the toolResult blocks that live in later user rows;
    /// bare tool-result rows and compaction summaries are not shown directly.
    static func rows(from stored: [SessionManager.StoredMessage]) -> [DisplayMessage] {
        var results: [String: (output: String, isError: Bool)] = [:]
        for message in stored {
            for case .toolResult(let id, let content, let isError, _) in message.content {
                results[id] = (content, isError)
            }
        }

        var rows: [DisplayMessage] = []
        for message in stored {
            if message.kind == MessageRecord.Kind.summary.rawValue { continue }
            let text = message.content.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined()
            let images = message.content.compactMap { if case .image(let i) = $0 { i } else { nil } }
            let toolUses = message.content.compactMap { block -> (id: String, name: String)? in
                if case .toolUse(let id, let name, _) = block { return (id, name) }
                return nil
            }
            switch message.role {
            case .user:
                let onlyToolResults = text.isEmpty && images.isEmpty && !message.content.isEmpty
                if onlyToolResults { continue } // shown via the paired tool rows
                rows.append(DisplayMessage(id: message.id, role: .user, text: text, images: images))
            default:
                if !text.isEmpty {
                    rows.append(DisplayMessage(id: message.id, role: .assistant, text: text, images: images))
                }
                for use in toolUses {
                    let result = results[use.id]
                    rows.append(DisplayMessage(
                        id: use.id, role: .tool, text: result?.output ?? "",
                        isError: result?.isError ?? false,
                        toolName: use.name,
                        toolState: (result?.isError ?? false) ? .error : .done
                    ))
                }
            }
        }
        return rows
    }
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
    private var lastUserText: String?
    private var queuedProactive: [String] = []

    // Scroll-up lazy history (iMessage style): persisted turns older than this
    // session's in-memory rows load in pages as the user reaches the top.
    private(set) var hasOlderHistory = true
    private var historyCursor = Date.now // everything before launch is "older"
    private var historyLoadInFlight = false

    /// The system prompt is deliberately static — every dynamic fact (time,
    /// frontmost app, memory) rides in the user turn so the provider prompt
    /// cache stays valid across turns and sessions.
    private static let systemPrompt = """
    You are Jarvis, the assistant that lives in the notch at the top of this Mac's screen. \
    You are a fast, capable alternative to Siri: you answer questions, control the Mac, \
    manage calendars, reminders, mail, and notes, remember things across conversations, \
    and can see the screen when asked.

    ## Tools
    You have tools to inspect and act on this Mac. Prefer acting over describing: when the \
    user asks for something a tool can do, do it. Read-only tools run instantly; tools \
    that change anything ask the user for approval first — never promise an action \
    succeeded before its result comes back. If a tool fails, say what failed and try a \
    sensible alternative before giving up. Use `remember` when the user tells you \
    something worth keeping ("remember that…", preferences, facts about themselves).

    ## Style
    You live in a small panel: be brief. Lead with the answer, not preamble. One short \
    paragraph is the norm; use Markdown lists or code blocks only when structure genuinely \
    helps. Match the user's language. If you don't know, say so plainly. Never invent \
    facts about the user's machine, files, or calendar — check with a tool instead.

    A `<context>` block in the user's message carries the current date, time, frontmost \
    app, and relevant memories. Treat it as ground truth for "today", "tomorrow", and \
    similar references; never echo the block itself.
    """

    init(core: JarvisCore, sessions: SessionManager, agent: AgentServices) {
        self.core = core
        self.sessions = sessions
        self.agent = agent
        // Restore the tail of the conversation right away (iMessage-style):
        // relaunching shows where you left off; the greeting appears only when
        // there is no history at all. Scroll-up pages further back.
        loadOlderHistory()
        // A half-typed message survives a relaunch.
        let settings = core.settings
        Task { @MainActor [weak self] in
            if let draft = try? await settings.get(Self.draftKey, as: String.self),
               !draft.isEmpty, let self, self.input.isEmpty {
                self.input = draft
            }
        }
    }

    // MARK: - Draft persistence

    private static let draftKey = "draft_input"
    private var draftTask: Task<Void, Never>?

    /// Debounced draft save, called on every composer keystroke.
    func draftChanged() {
        draftTask?.cancel()
        let settings = core.settings
        let value = input
        draftTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            try? await settings.set(Self.draftKey, to: value)
        }
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

        lastUserText = userText
        messages.append(DisplayMessage(id: UUID().uuidString, role: .user, text: trimmed, images: images))

        input = ""
        attachments = []
        errorText = nil
        phase = .responding
        activeAssistantID = nil
        pendingToolResults = []

        // The message left the composer — clear the persisted draft.
        draftTask?.cancel()
        let settingsStore = core.settings
        Task { try? await settingsStore.set(Self.draftKey, to: "") }

        let runID = UUID().uuidString
        let artifactStore = agent.artifactStore
        let tools = agent.tools
        let gate = agent.gate
        let runStore = agent.runStore
        let sessions = self.sessions
        let memory = self.memory
        let adapter = resolved.adapter
        let effort = resolved.effort
        let model = resolved.model
        let providerLabel = resolved.account.provider
        var usage = Usage()

        runTask = Task { [weak self] in
            await runStore.createRun(id: runID, kind: "foreground", segmentID: nil, initiator: "user")
            let turn = try? await sessions.beginUserTurn()
            if turn?.startedNewSegment == true {
                // Fresh segment = fresh context; the closed segment's content is
                // handed to memory extraction, not resent forever.
                self?.transcript = []
            }

            // Dynamic per-turn context (date/time, frontmost app, memory) rides
            // in the user turn so the system prompt stays byte-stable for caching.
            let memoryContext = await memory?.context(for: userText)
            let userMessage = NeutralMessage.user(
                Self.contextBlock(memory: memoryContext) + "\n\n" + userText,
                images: images
            )
            guard let self else { return }
            self.transcript.append(userMessage)
            _ = try? await sessions.append(role: .user, content: [.text(userText)] + images.map(ContentBlock.image), status: .complete)
            await self.compactIfNeeded(accountID: resolved.account.id, model: model)

            let loop = AgentLoop(
                adapter: adapter, tools: tools, gate: gate,
                config: .init(model: model, system: Self.systemPrompt, effort: effort, maxTokens: 8192, maxTurns: 12),
                spill: { name, content in await artifactStore.spill(runID: runID, toolName: name, content: content) }
            )

            var completion: StopReason?
            for await event in loop.run(initial: self.transcript, runID: runID) {
                ChatDebugLog.write(event)
                switch event {
                case .runStarted:
                    break
                case .textDelta(let t):
                    self.appendToAssistant(t, thinking: false)
                case .thinkingDelta(let t):
                    self.appendToAssistant(t, thinking: true)
                case .assistantMessage(let m):
                    await self.flushPendingToolResults(runID: runID)
                    self.finalizeAssistant(m)
                    self.transcript.append(m)
                    // Persist every assistant turn — including tool-only turns —
                    // so History and relaunch see the full run, not just prose.
                    if !m.content.isEmpty {
                        _ = try? await sessions.append(role: .assistant, content: m.content, status: .complete,
                                                       runId: runID, model: model, provider: providerLabel)
                    }
                case .toolCallStarted(let id, let name, let input):
                    self.messages.append(DisplayMessage(id: id, role: .tool, toolName: name, toolState: .running))
                    await runStore.toolStarted(id: id, runID: runID, name: name, input: input)
                case .toolCallFinished(let id, let output, let isError, let artifactID):
                    self.updateToolRow(id: id, output: output, isError: isError)
                    self.pendingToolResults.append(.toolResult(toolUseId: id, content: output, isError: isError, images: []))
                    await runStore.toolFinished(id: id, state: isError ? "error" : "done", preview: output, artifactID: artifactID)
                case .usage(let u):
                    usage.add(u)
                case .completed(let reason):
                    completion = reason
                    await self.flushPendingToolResults(runID: runID)
                case .aborted:
                    break // handled below — cancellation usually ends iteration before this arrives
                case .failed(let message):
                    self.showFailure(message)
                }
            }

            // Cancellation ends stream iteration before `.aborted` can be
            // delivered, so abort handling must live HERE, not in the loop.
            if Task.isCancelled {
                self.repairDanglingTools(runID: runID)
                self.markActiveAborted()
            }
            if completion == .refusal {
                self.showFailure("The model declined to answer this request.")
            }

            self.finishRun(runID: runID, usage: usage, interrupted: Task.isCancelled,
                           accountID: resolved.account.id, model: model)
        }
    }

    /// End-of-run persistence runs in an unstructured task: GRDB honors task
    /// cancellation, so doing these writes inside the cancelled run task would
    /// silently drop them (runs stuck "running" forever).
    private func finishRun(runID: String, usage: Usage, interrupted: Bool, accountID: String, model: String) {
        let runStore = agent.runStore
        let core = self.core
        let status = interrupted ? "cancelled" : (errorText == nil ? "done" : "error")
        let errorText = self.errorText
        Task { @MainActor [weak self] in
            let cost = await core.capability(forAccount: accountID, model: model)?.cost(of: usage)
            await runStore.finishRun(id: runID, status: status, usage: usage, error: errorText, costUSD: cost)
            guard let self else { return }
            self.phase = .idle
            self.deliverQueuedProactive()
            if !interrupted { self.onRunComplete?() }
            self.memory?.turnCompleted() // debounced memory extraction after each user turn
        }
    }

    /// Re-send the last user message (retry affordance after a failure).
    func retryLast() {
        guard phase == .idle, let last = lastUserText, !last.isEmpty else { return }
        errorText = nil
        input = last
        send()
    }

    func interrupt() {
        runTask?.cancel()
    }

    // MARK: - Per-turn context

    private static let contextDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
        return f
    }()

    private static func contextBlock(memory: String?) -> String {
        var lines = ["<context>"]
        lines.append("Now: \(contextDateFormatter.string(from: .now)) (\(TimeZone.current.identifier))")
        if let app = NSWorkspace.shared.frontmostApplication?.localizedName {
            lines.append("Frontmost app: \(app)")
        }
        if let memory, !memory.isEmpty {
            lines.append(memory)
        }
        lines.append("</context>")
        return lines.joined(separator: "\n")
    }

    /// Pre-call compaction (hermes pattern): when the transcript nears the
    /// model's context limit, the middle is folded into one summary message —
    /// persisted as a kind='summary' row so restore sees the same view.
    private func compactIfNeeded(accountID: String, model: String) async {
        let limit = await core.capability(forAccount: accountID, model: model)?.contextLimit ?? 200_000
        guard let plan = TranscriptCompactor.plan(transcript, contextLimit: limit, toolSchemas: agent.tools.schemas)
        else { return }

        // ponytail: aux/brain summarizes; Phase 3 puts the local model first.
        let summary = await summarize(plan.middle)
            ?? "Earlier conversation: \(plan.middle.count) turns omitted to fit the context window."
        let summaryText = "[Conversation summary]\n\(summary)"
        transcript = plan.head + [.user(summaryText)] + plan.tail
        _ = try? await sessions.append(role: .user, content: [.text(summaryText)], status: .complete, kind: .summary)
    }

    private func summarize(_ middle: [NeutralMessage]) async -> String? {
        guard let resolved = core.resolve(.aux) ?? core.resolve(.brain) else { return nil }
        let request = ModelRequest(
            model: resolved.model,
            system: """
            Summarize this conversation history compactly for the assistant's own memory. \
            Keep: the user's goals, decisions made, facts learned, tool findings, and \
            unresolved threads. Omit pleasantries. Plain prose, no preamble.
            """,
            messages: [.user(TranscriptCompactor.renderForSummary(middle))],
            maxTokens: 500
        )
        let engine = ChatEngine(adapter: resolved.adapter)
        var text = ""
        for await event in engine.run(request) {
            if case .assistantMessage(let m) = event { text = m.plainText }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func addAttachment(_ attachment: Attachment) { attachments.append(attachment) }
    func removeAttachment(_ id: String) { attachments.removeAll { $0.id == id } }

    /// Jarvis-initiated message (nudge, cron brief, heartbeat). Appears in chat + glows the notch.
    /// Queued while a run is streaming — splicing an assistant message between a
    /// tool_use and its results would corrupt the transcript.
    func receiveProactive(_ body: String) {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if phase == .responding {
            queuedProactive.append(text)
            return
        }
        deliverProactive(text)
    }

    private func deliverQueuedProactive() {
        guard phase == .idle else { return }
        for text in queuedProactive { deliverProactive(text) }
        queuedProactive = []
    }

    private func deliverProactive(_ text: String) {
        messages.append(DisplayMessage(id: UUID().uuidString, role: .assistant, text: text))
        transcript.append(.assistant(text))
        hasUnreadProactive = true
        let sessions = self.sessions
        Task {
            // Proactive messages belong to history too (survive relaunch).
            _ = try? await sessions.beginUserTurn()
            _ = try? await sessions.append(role: .assistant, content: [.text(text)], status: .complete)
        }
    }

    func markProactiveRead() { hasUnreadProactive = false }

    /// Prepends one page of persisted conversation (all sessions, newest first)
    /// when the user scrolls to the top of the transcript.
    func loadOlderHistory() {
        guard hasOlderHistory, !historyLoadInFlight else { return }
        historyLoadInFlight = true
        let cutoff = historyCursor
        let sessions = self.sessions
        Task { @MainActor [weak self] in
            let older = await sessions.messagesBefore(cutoff)
            guard let self else { return }
            self.historyLoadInFlight = false
            guard !older.isEmpty else {
                self.hasOlderHistory = false
                return
            }
            self.historyCursor = older.first?.createdAt ?? cutoff
            let rows = DisplayMessage.rows(from: older)
            self.messages.insert(contentsOf: rows, at: 0)
            if older.count < 30 { self.hasOlderHistory = false }
        }
    }

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

    /// Appends buffered tool results to the transcript AND persists them, so
    /// tool turns survive relaunch. Awaited inline to keep message seq ordered.
    private func flushPendingToolResults(runID: String) async {
        guard !pendingToolResults.isEmpty else { return }
        let blocks = pendingToolResults
        pendingToolResults = []
        transcript.append(NeutralMessage(role: .user, content: blocks))
        _ = try? await sessions.append(role: .user, content: blocks, status: .complete, runId: runID)
    }

    /// After an abort, synthesize results for any tool_use left without one so
    /// the next model call sees a valid transcript. Persistence goes through an
    /// unstructured task — GRDB honors cancellation and this path only runs on
    /// a cancelled task.
    private func repairDanglingTools(runID: String) {
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
        guard !pendingToolResults.isEmpty else { return }
        let blocks = pendingToolResults
        pendingToolResults = []
        transcript.append(NeutralMessage(role: .user, content: blocks))
        let sessions = self.sessions
        Task {
            _ = try? await sessions.append(role: .user, content: blocks, status: .complete, runId: runID)
        }
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

/// Event-flow diagnostics: appends one line per AgentEvent to the file named by
/// JARVIS_CHAT_LOG. Inert in normal runs.
enum ChatDebugLog {
    nonisolated(unsafe) private static let handle: FileHandle? = {
        guard let path = ProcessInfo.processInfo.environment["JARVIS_CHAT_LOG"] else { return nil }
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }()

    static func write(_ event: AgentEvent) {
        guard let handle else { return }
        let line: String
        switch event {
        case .runStarted: line = "runStarted"
        case .textDelta(let t): line = "textDelta(\(t.count)ch)"
        case .thinkingDelta(let t): line = "thinkingDelta(\(t.count)ch)"
        case .assistantMessage(let m): line = "assistantMessage(plainText=\(m.plainText.count)ch, blocks=\(m.content.count))"
        case .toolCallStarted(_, let name, _): line = "toolCallStarted(\(name))"
        case .toolCallFinished(let id, _, let isError, _): line = "toolCallFinished(\(id), error=\(isError))"
        case .usage(let u): line = "usage(in=\(u.inputTokens), out=\(u.outputTokens))"
        case .completed(let r): line = "completed(\(r))"
        case .aborted: line = "aborted"
        case .failed(let m): line = "failed(\(m))"
        }
        try? handle.write(contentsOf: Data((line + "\n").utf8))
    }
}
