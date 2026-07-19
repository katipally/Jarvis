import EventKit
import Foundation
import GRDB
import JAgent
import JLocal
import JProactive
import JScreen
import JStore

/// The proactivity engine. Context switches run a text-only GATE → GENERATE →
/// CRITIC funnel on the on-device model (mostly rejected); the 30s cron loop
/// fires scheduled jobs, composes the morning brief / evening recap for its
/// reserved builtin ids, and surfaces commitments as they come due; a periodic
/// heartbeat proposes timely nudges that must still pass the CRITIC. Everything
/// is gated by the nudge funnel, a persisted daily token budget, a master mute,
/// and a dismissal-driven cooldown backoff. Delivery = chat message + notch glow
/// + a real system notification.
@MainActor
final class ProactivityService {
    private let core: JarvisCore
    private let chat: ChatStore
    private let agent: AgentServices
    private let localFirst: LocalFirst
    private let tasks: TaskStore
    private let notifications: NotificationService
    private weak var memory: MemoryService?

    /// Local, per-call-tuned copy of the shared funnel (aggressiveness + backoff).
    private var funnel: NudgeFunnel

    private var cronTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var lastEval = Date.distantPast

    static let morningBriefID = "builtin:morning_brief"
    static let eveningRecapID = "builtin:evening_recap"

    // MARK: - Persisted state (SettingsStore)

    private struct BudgetState: Codable, Sendable { var day: Date; var tokensSpent: Int }

    private var muted = false
    private var dailyTokenLimit = 200_000
    private var budget = BudgetState(day: Calendar.current.startOfDay(for: .now), tokensSpent: 0)
    private var funnelState = NudgeFunnelState()

    private static let backgroundSystem = """
    You are Jarvis running a background task. Be concise. You may use read-only tools \
    to gather context. Produce a short, directly useful result for the user.
    """
    private static let gateInstructions = """
    You decide whether Jarvis should interrupt the user based on what's on their screen \
    right now. Say relevant ONLY for a concrete mistake, a time-sensitive action, or a \
    non-obvious useful connection to what you know about them. Idle browsing, reading, or \
    ordinary work is NOT relevant. Default to not relevant.
    """
    private static let generateInstructions = """
    Write the single most useful thing Jarvis could say to the user about what's on their \
    screen — like a sharp friend texting one line. No greeting, no filler, no "I noticed".
    """
    private static let criticInstructions = """
    You are the last gate before Jarvis interrupts the user. Approve ONLY if the message \
    tells them something genuinely new and useful they don't already know and would want \
    right now. Most proposals should be rejected. Default to not approving.
    """
    private static let briefInstructions = """
    Write a short, warm morning brief from these facts — 2-4 sentences. Lead with what \
    matters most today (next meeting, key task, or commitment). No headings, no bullet \
    dump, no preamble. If there's genuinely nothing, say the day looks open.
    """
    private static let recapInstructions = """
    Write a short end-of-day recap from these facts — 2-3 sentences. Note what's still \
    open or due, and anything to line up for tomorrow. No headings, no preamble.
    """

    init(core: JarvisCore, chat: ChatStore, agent: AgentServices,
         localFirst: LocalFirst, tasks: TaskStore, notifications: NotificationService,
         memory: MemoryService?) {
        self.core = core
        self.chat = chat
        self.agent = agent
        self.localFirst = localFirst
        self.tasks = tasks
        self.notifications = notifications
        self.memory = memory
        self.funnel = agent.funnel
    }

    func start() {
        // Feed dismissal backoff from banner dismissals.
        notifications.onDismiss = { [weak self] in self?.feedback(dismissed: true) }
        Task { [weak self] in
            await self?.loadBudget()
            await self?.reloadConfig()
        }
        cronTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
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

    /// One 30s tick: refresh settings-derived config, fire cron + briefs, and
    /// surface commitments coming due.
    private func tick() async {
        await reloadConfig()
        await fireDueCron()
        await checkCommitments()
    }

    // MARK: - Config

    private func setting<T: Codable & Sendable>(_ key: String, default def: T) async -> T {
        ((try? await core.settings.get(key, as: T.self)) ?? nil) ?? def
    }

    private func reloadConfig() async {
        muted = await setting("proactive_muted", default: false)
        dailyTokenLimit = await setting("proactive_token_budget", default: 200_000)
        applyAggressiveness(await setting("proactive_aggressiveness", default: "balanced"))

        // Dismissal backoff decays back toward 1 across quiet days.
        let stored: NudgeFunnelState = await setting("funnel_state", default: NudgeFunnelState())
        let decayed = stored.decayed()
        if decayed != stored { await persistFunnelState(decayed) }
        funnelState = decayed
        funnel.cooldownMultiplier = decayed.multiplier

        await rolloverIfNeeded()
        await seedBuiltins()
    }

    private func applyAggressiveness(_ level: String) {
        switch level {
        case "relaxed": funnel.globalCooldown = 40 * 60; funnel.dailyCap = 4
        case "eager":   funnel.globalCooldown = 10 * 60; funnel.dailyCap = 16
        default:        funnel.globalCooldown = 20 * 60; funnel.dailyCap = 8
        }
    }

    private func seedBuiltins() async {
        let briefTime = await setting("brief_time", default: "09:00")
        await agent.cronStore.ensureBuiltin(
            id: Self.morningBriefID, name: "Morning brief",
            cronExpr: Self.cronExpr(fromHHmm: briefTime) ?? "0 9 * * *", enabled: !muted)

        let recapEnabled = await setting("recap_enabled", default: false)
        let recapTime = await setting("recap_time", default: "18:30")
        await agent.cronStore.ensureBuiltin(
            id: Self.eveningRecapID, name: "Evening recap",
            cronExpr: Self.cronExpr(fromHHmm: recapTime) ?? "30 18 * * *", enabled: recapEnabled && !muted)
    }

    /// "HH:mm" → a daily 5-field cron expression "m h * * *".
    static func cronExpr(fromHHmm value: String) -> String? {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return "\(m) \(h) * * *"
    }

    // MARK: - Context switch (text-only GATE → GENERATE → CRITIC)

    func onContextSwitch(_ frame: CapturedFrame) {
        Task { await evaluateSwitch(frame) }
    }

    private func evaluateSwitch(_ frame: CapturedFrame) async {
        guard !muted, hasBudget() else { return }
        guard Date.now.timeIntervalSince(lastEval) > 90 else { return }
        guard await funnel.canDeliver(dedupKey: nil) else { return }
        lastEval = .now

        let title = [frame.appName, frame.windowTitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
        let ocr = await latestOCRText() ?? ""
        let mem = await memory?.context(for: title.isEmpty ? "current activity" : title) ?? ""
        let context = """
        Frontmost: \(title.isEmpty ? "unknown" : title)
        On-screen text (truncated): \(String(ocr.prefix(1500)))
        \(mem)
        """

        // GATE — default reject; a nil result (no on-device model) also rejects.
        guard let gate = await localFirst.generate(NudgeGate.self, instructions: Self.gateInstructions, prompt: context),
              gate.isRelevant else { return }

        // GENERATE
        guard let draft = await localFirst.generate(NudgeDraft.self, instructions: Self.generateInstructions, prompt: context),
              !draft.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // CRITIC — most drafts should be rejected.
        guard await passesCritic(draft.message, context: context) else { return }
        guard await funnel.canDeliver(dedupKey: draft.topic) else { return }
        await deliver(title: "Jarvis", body: draft.message, trigger: "context_switch", dedupKey: draft.topic, frameID: frame.appBundleID)
    }

    private func passesCritic(_ message: String, context: String) async -> Bool {
        let verdict = await localFirst.generate(
            CriticVerdict.self, instructions: Self.criticInstructions,
            prompt: "Proposed nudge: \(message)\n\nContext:\n\(context)")
        return verdict?.approve ?? false
    }

    /// Most-recent captured frame's OCR text, if any. Read straight off the
    /// shared DB (TaskStore already carries the handle) — no vision call.
    private func latestOCRText() async -> String? {
        (try? await tasks.database.reader.read { db in
            try String.fetchOne(db, sql: """
                SELECT ocr_text FROM screen_frame
                WHERE ocr_text IS NOT NULL AND ocr_text <> ''
                ORDER BY ts DESC LIMIT 1
                """)
        }) ?? nil
    }

    // MARK: - Cron + briefs

    private func fireDueCron() async {
        for job in await agent.cronStore.dueJobs() {
            if job.id == Self.morningBriefID || job.id == Self.eveningRecapID {
                let text = await composeBrief(evening: job.id == Self.eveningRecapID)
                await agent.cronStore.markRan(id: job.id, status: text.isEmpty ? "empty" : "done")
                await deliver(title: job.name, body: text, trigger: "brief", dedupKey: nil, frameID: nil)
                continue
            }
            guard hasBudget() else { continue }
            let (text, usage) = await runBackground(prompt: job.prompt, kind: "cron", label: "cron: \(job.name)")
            addBudget(usage.inputTokens + usage.outputTokens)
            await agent.cronStore.markRan(id: job.id, status: text.isEmpty ? "empty" : "done")
            await deliver(title: job.name, body: text, trigger: "cron", dedupKey: "cron:\(job.id)", frameID: nil)
        }
    }

    private func composeBrief(evening: Bool) async -> String {
        let events = await todaysCalendarEvents()
        let openTasks = await tasks.tasks(statuses: [.open, .suggested])
        let dueToday = await tasks.dueCommitments(by: endOfToday())
        let mem = await memory?.context(for: evening ? "today's accomplishments" : "today's priorities") ?? ""

        var lines: [String] = ["Calendar today:"]
        lines.append(events.isEmpty ? "- (nothing scheduled)" : events.map { "- \($0)" }.joined(separator: "\n"))
        if !openTasks.isEmpty {
            lines.append("Tasks:")
            lines.append(openTasks.prefix(8).map { "- \($0.text)" }.joined(separator: "\n"))
        }
        if !dueToday.isEmpty {
            lines.append("Commitments due today:")
            lines.append(dueToday.map { "- \($0.text)" }.joined(separator: "\n"))
        }
        if !mem.isEmpty { lines.append(mem) }
        let facts = lines.joined(separator: "\n")

        // On-device → aux → brain; raw facts if nothing is configured at all.
        return await localFirst.text(
            instructions: evening ? Self.recapInstructions : Self.briefInstructions,
            prompt: facts, maxTokens: 400) ?? facts
    }

    private func todaysCalendarEvents() async -> [String] {
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToEvents()) == true else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).prefix(20).map {
            "\($0.startDate.formatted(date: .omitted, time: .shortened)) \($0.title ?? "(untitled)")"
        }
    }

    private func endOfToday() -> Date {
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        return cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
    }

    // MARK: - Commitments

    private func checkCommitments() async {
        guard !muted else { return }
        let soon = Date.now.addingTimeInterval(15 * 60)
        for c in await tasks.dueCommitments(by: soon) {
            await tasks.setCommitmentStatus(c.id, .notified)
            await deliver(title: "Reminder", body: commitmentReminder(c),
                          trigger: "commitment", dedupKey: "commitment:\(c.id)", frameID: nil)
        }
    }

    private func commitmentReminder(_ c: CommitmentRow) -> String {
        if let due = c.dueAt {
            return "You said you'd \(c.text) by \(due.formatted(date: .omitted, time: .shortened))."
        }
        return "Reminder: you said you'd \(c.text)."
    }

    // MARK: - Heartbeat

    private func heartbeatTick() async {
        await reloadConfig()
        guard !muted, hasBudget(), await funnel.canDeliver(dedupKey: nil) else { return }
        let prompt = """
        It is currently \(Date.now.formatted(date: .complete, time: .shortened)). Considering the \
        time of day and anything you know about the user, is there something genuinely useful and \
        timely to tell them right now? If yes, reply with one short helpful message. If not, reply \
        with exactly: NOTHING.
        """
        let (text, usage) = await runBackground(prompt: prompt, kind: "heartbeat", label: "heartbeat")
        addBudget(usage.inputTokens + usage.outputTokens)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.uppercased().hasPrefix("NOTHING"), trimmed.count > 4 else {
            await agent.cronStore.setHeartbeatRun(.now, result: "nothing")
            return
        }
        // The heartbeat result must clear the same CRITIC before it can interrupt.
        guard await passesCritic(trimmed, context: "Time-based heartbeat suggestion.") else {
            await agent.cronStore.setHeartbeatRun(.now, result: "vetoed")
            return
        }
        await agent.cronStore.setHeartbeatRun(.now, result: "nudged")
        guard await funnel.canDeliver(dedupKey: "heartbeat") else { return }
        await deliver(title: "Jarvis", body: trimmed, trigger: "heartbeat", dedupKey: "heartbeat", frameID: nil)
    }

    // MARK: - Delivery

    private func deliver(title: String, body: String, trigger: String, dedupKey: String?, frameID: String?) async {
        let clean = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !muted else { return }
        await funnel.record(NudgeRow(trigger: trigger, frameId: frameID, dedupKey: dedupKey, title: title, body: clean))
        notifications.post(title: title, body: clean)
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

    // MARK: - Budget (persisted daily)

    private func loadBudget() async {
        budget = await setting("proactive_budget",
                               default: BudgetState(day: Calendar.current.startOfDay(for: .now), tokensSpent: 0))
        await rolloverIfNeeded()
    }

    private func rolloverIfNeeded() async {
        let today = Calendar.current.startOfDay(for: .now)
        if budget.day != today {
            budget = BudgetState(day: today, tokensSpent: 0)
            await persistBudget()
        }
    }

    private func hasBudget() -> Bool { budget.tokensSpent < dailyTokenLimit }

    private func addBudget(_ tokens: Int) {
        guard tokens > 0 else { return }
        budget.tokensSpent += tokens
        Task { await persistBudget() }
    }

    private func persistBudget() async { try? await core.settings.set("proactive_budget", to: budget) }

    // MARK: - Dismissal backoff

    /// Called when the user dismisses a proactive banner: 4x the cooldown so
    /// Jarvis backs off, persisted so it survives relaunch and decays daily.
    func feedback(dismissed: Bool) {
        guard dismissed else { return }
        let bumped = funnelState.bumped()
        funnelState = bumped
        funnel.cooldownMultiplier = bumped.multiplier
        Task { await persistFunnelState(bumped) }
    }

    private func persistFunnelState(_ state: NudgeFunnelState) async {
        try? await core.settings.set("funnel_state", to: state)
    }
}
