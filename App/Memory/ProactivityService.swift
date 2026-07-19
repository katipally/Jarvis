import Foundation
import JAgent
import JProactive
import JScreen
import JStore

/// The proactivity engine: evaluates context switches (one frame → aux "worth
/// interrupting?"), fires cron jobs, and runs a periodic heartbeat — delivering
/// results as Jarvis-initiated messages, gated by the nudge funnel and a daily
/// token budget. Background runs use the safe (read-only) tool registry.
@MainActor
final class ProactivityService {
    private let core: JarvisCore
    private let chat: ChatStore
    private let agent: AgentServices

    private var cronTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var lastEval = Date.distantPast

    // Daily token budget (input + output) for all proactive/background spend.
    // ponytail: in-memory counter, resets on relaunch; persist to heartbeat_state
    // if restart-abuse ever matters.
    private let dailyTokenLimit = 200_000
    private var budgetSpent = 0
    private var budgetDay = Calendar.current.startOfDay(for: .now)

    private static let backgroundSystem = """
    You are Jarvis running a background task. Be concise. You may use read-only tools \
    to gather context. Produce a short, directly useful result for the user.
    """

    init(core: JarvisCore, chat: ChatStore, agent: AgentServices) {
        self.core = core
        self.chat = chat
        self.agent = agent
    }

    func start() {
        cronTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fireDueCron()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1200)) // 20 min
                await self?.heartbeatTick()
            }
        }
    }

    func stop() {
        cronTask?.cancel()
        heartbeatTask?.cancel()
    }

    // MARK: - Context switch

    func onContextSwitch(_ frame: CapturedFrame) {
        Task { await evaluateSwitch(frame) }
    }

    private func evaluateSwitch(_ frame: CapturedFrame) async {
        guard hasBudget() else { return }
        guard Date.now.timeIntervalSince(lastEval) > 90 else { return }
        // Global cooldown gate BEFORE spending on the model.
        guard await agent.funnel.canDeliver(dedupKey: nil) else { return }
        guard let resolved = core.resolve(.aux) ?? core.resolve(.brain) else { return }
        lastEval = .now

        let system = """
        You decide whether Jarvis should proactively interrupt the user. Be very \
        conservative — only nudge if you can offer something specific and genuinely \
        useful right now. Respond ONLY as JSON: \
        {"nudge": true/false, "message": "one short helpful sentence", "topic": "short-key"}.
        """
        let user = "The user just switched to \(frame.appName ?? "an app"). Here is their screen — is there anything genuinely useful to offer?"
        let request = ModelRequest(
            model: resolved.model, system: system,
            messages: [.user(user, images: [ImageSource(mediaType: "image/jpeg", base64Data: frame.base64)])],
            maxTokens: 300
        )
        let (text, usage) = await collect(resolved.adapter, request)
        addBudget(usage.inputTokens + usage.outputTokens)

        let decision = parseDecision(text)
        guard decision.nudge, !decision.message.isEmpty else { return }
        guard await agent.funnel.canDeliver(dedupKey: decision.topic) else { return }
        await deliver(body: decision.message, trigger: "context_switch", dedupKey: decision.topic, frameID: nil)
    }

    // MARK: - Cron

    private func fireDueCron() async {
        guard hasBudget() else { return }
        for job in await agent.cronStore.dueJobs() {
            let (text, usage) = await runBackground(prompt: job.prompt, kind: "cron", label: "cron: \(job.name)")
            addBudget(usage.inputTokens + usage.outputTokens)
            await agent.cronStore.markRan(id: job.id, status: text.isEmpty ? "empty" : "done")
            await deliver(body: text, trigger: "cron", dedupKey: "cron:\(job.id)", frameID: nil)
        }
    }

    // MARK: - Heartbeat

    private func heartbeatTick() async {
        guard hasBudget(), await agent.funnel.canDeliver(dedupKey: nil) else { return }
        let prompt = """
        It is currently \(Date.now.formatted(date: .complete, time: .shortened)). Considering the \
        time of day and anything you know about the user, is there something genuinely useful and \
        timely to tell them right now? If yes, reply with one short helpful message. If not, reply \
        with exactly: NOTHING.
        """
        let (text, usage) = await runBackground(prompt: prompt, kind: "heartbeat", label: "heartbeat")
        addBudget(usage.inputTokens + usage.outputTokens)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        await agent.cronStore.setHeartbeatRun(.now, result: trimmed.isEmpty ? "nothing" : "nudged")
        guard !trimmed.isEmpty, !trimmed.uppercased().hasPrefix("NOTHING"), trimmed.count > 4 else { return }
        guard await agent.funnel.canDeliver(dedupKey: "heartbeat") else { return }
        await deliver(body: trimmed, trigger: "heartbeat", dedupKey: "heartbeat", frameID: nil)
    }

    // MARK: - Delivery + runners

    private func deliver(body: String, trigger: String, dedupKey: String?, frameID: String?) async {
        let clean = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        await agent.funnel.record(NudgeRow(trigger: trigger, frameId: frameID, dedupKey: dedupKey, body: clean))
        chat.receiveProactive(clean)
    }

    /// Runs a background agent turn AND records it like a foreground run —
    /// kind/label/tool calls/tokens/cost all land in Activity.
    private func runBackground(prompt: String, kind: String, label: String) async -> (String, Usage) {
        guard let resolved = core.resolve(.brain) else { return ("", Usage()) }
        let runID = UUID().uuidString
        let runStore = agent.runStore
        await runStore.createRun(id: runID, kind: kind, segmentID: nil, initiator: "jarvis", label: label)
        let loop = AgentLoop(
            adapter: resolved.adapter, tools: agent.tools, gate: agent.gate,
            config: .init(model: resolved.model, system: Self.backgroundSystem, effort: resolved.effort,
                          maxTokens: 1500, maxTurns: 6, isBackground: true)
        )
        var text = ""
        var usage = Usage()
        for await event in loop.run(initial: [.user(prompt)], runID: runID) {
            switch event {
            case .assistantMessage(let m) where !m.plainText.isEmpty: text = m.plainText
            case .toolCallStarted(let id, let name, let input):
                await runStore.toolStarted(id: id, runID: runID, name: name, input: input)
            case .toolCallFinished(let id, let output, let isError, let artifactID):
                await runStore.toolFinished(id: id, state: isError ? "error" : "done", preview: output, artifactID: artifactID)
            case .usage(let u): usage.add(u)
            default: break
            }
        }
        let cost = await core.capability(forAccount: resolved.account.id, model: resolved.model)?.cost(of: usage)
        await runStore.finishRun(id: runID, status: text.isEmpty ? "empty" : "done", usage: usage, error: nil, costUSD: cost)
        return (text, usage)
    }

    private func collect(_ adapter: any ProviderAdapter, _ request: ModelRequest) async -> (String, Usage) {
        let engine = ChatEngine(adapter: adapter)
        var text = ""
        var usage = Usage()
        for await event in engine.run(request) {
            if case .assistantMessage(let m) = event { text = m.plainText }
            if case .usage(let u) = event { usage = u }
        }
        return (text, usage)
    }

    // MARK: - Budget

    private func hasBudget() -> Bool {
        rolloverBudget()
        return budgetSpent < dailyTokenLimit
    }

    private func addBudget(_ tokens: Int) {
        rolloverBudget()
        budgetSpent += tokens
    }

    private func rolloverBudget() {
        let today = Calendar.current.startOfDay(for: .now)
        if today != budgetDay {
            budgetDay = today
            budgetSpent = 0
        }
    }

    // MARK: - Parsing

    private struct Decision { var nudge: Bool; var message: String; var topic: String? }

    private func parseDecision(_ text: String) -> Decision {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let data = String(text[start...end]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Decision(nudge: false, message: "", topic: nil)
        }
        return Decision(
            nudge: (obj["nudge"] as? Bool) ?? false,
            message: (obj["message"] as? String) ?? "",
            topic: obj["topic"] as? String
        )
    }
}
