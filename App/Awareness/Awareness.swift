import EventKit
import Foundation
import GRDB
import JAgent
import JKnowledge
import JLocal
import JMind
import JProactive
import JScreen
import JStore

/// Awareness — Jarvis's single proactive engine (`observe → reflect → decide`).
/// Two paths, both defaulting to silence (openhuman's model):
///
///   HEARTBEAT — periodic tick → per-world diff since checkpoint → nothing
///   changed = a free quiet tick (zero LLM calls) → else a small reflection
///   (lenses: deadlines/risks/patterns/opportunities) that may note facts, add
///   tasks, or — high bar — notify.
///
///   TRIGGERS — events (world syncs, context switches) → dedupe window →
///   per-source token bucket → tiny on-device triage (drop/acknowledge/react/
///   escalate, bias drop) → sliding-hour promotion budget (downgrade, never
///   discard) → serial queue → background run and/or notify.
///
/// Plus a 60s staged-delivery loop (calendar meetings heads_up/final_call/
/// starting_now, commitments soon/due, content-key sent-dedup).
///
/// EVERY verdict — including "stayed quiet" — lands in the decision table.
@MainActor
final class Awareness {
    private let core: JarvisCore
    private let chat: ChatStore
    private let agent: AgentServices
    private let localFirst: LocalFirst
    private let tasks: TaskStore
    private let notifications: NotificationService
    private weak var knowledge: KnowledgeService?
    private let database: JarvisDatabase

    private var admission = TriggerAdmission()
    private var promotionBudget = PromotionBudget(maxPerHour: 4)
    private var triggerQueue: [Trigger] = []
    private var pumping = false

    private var cronTask: Task<Void, Never>?
    private var deliveryTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    /// Global context-switch throttle (the tiny triage model must not run on
    /// every Cmd-Tab of a fast multitasking burst).
    private var lastSwitchEval = Date.distantPast

    static let morningBriefID = "builtin:morning_brief"
    static let eveningRecapID = "builtin:evening_recap"

    // MARK: - Persisted state

    private struct BudgetState: Codable, Sendable { var day: Date; var tokensSpent: Int }

    private var muted = false
    private var dailyTokenLimit = 200_000
    private var budget = BudgetState(day: Calendar.current.startOfDay(for: .now), tokensSpent: 0)
    /// Min gap between agent-initiated nudges (posture-dependent). Staged
    /// deliveries (meetings/commitments) are exempt — those must fire on time.
    private var nudgeCooldown: TimeInterval = 20 * 60
    /// Max agent-initiated nudges per day (posture-dependent), counted from
    /// the nudge table so it survives relaunch.
    private var dailyNudgeCap = 8
    private var heartbeatInterval: TimeInterval = 600

    init(core: JarvisCore, chat: ChatStore, agent: AgentServices,
         localFirst: LocalFirst, tasks: TaskStore, notifications: NotificationService,
         knowledge: KnowledgeService?, database: JarvisDatabase) {
        self.core = core
        self.chat = chat
        self.agent = agent
        self.localFirst = localFirst
        self.tasks = tasks
        self.notifications = notifications
        self.knowledge = knowledge
        self.database = database
    }

    func start() {
        notifications.onDismiss = { [weak self] in
            guard let self else { return }
            // Mark the dismissed nudge — maybeNudge derives its backoff
            // multiplier from recent dismissals, so this has a mechanical
            // effect on cadence.
            Task {
                _ = try? await self.database.writer.write { db in
                    try db.execute(sql: """
                        UPDATE nudge SET state = 'dismissed' WHERE id =
                          (SELECT id FROM nudge WHERE state = 'shown' ORDER BY created_at DESC LIMIT 1)
                        """)
                }
            }
        }
        Task { [weak self] in
            await self?.loadBudget()
            await self?.reloadConfig()
        }
        cronTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.reloadConfig()
                await self?.fireDueCron()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        deliveryTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.deliveryTick()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        heartbeatTask = Task { [weak self] in
            // Resume the cadence where the last launch left off.
            let interval = self?.heartbeatInterval ?? 600
            var delay = interval
            if let last = await self?.agent.cronStore.heartbeatLastRun() {
                delay = max(60, interval - Date.now.timeIntervalSince(last))
            }
            try? await Task.sleep(for: .seconds(delay))
            while !Task.isCancelled {
                await self?.heartbeatTick()
                try? await Task.sleep(for: .seconds(self?.heartbeatInterval ?? 600))
            }
        }
    }

    func stop() {
        for task in [cronTask, deliveryTask, heartbeatTask] { task?.cancel() }
    }

    // MARK: - Config

    private func setting<T: Codable & Sendable>(_ key: String, default def: T) async -> T {
        ((try? await core.settings.get(key, as: T.self)) ?? nil) ?? def
    }

    private func reloadConfig() async {
        let wasMuted = muted
        muted = await setting("proactive_muted", default: false)
        if wasMuted && !muted { notifications.requestAuth() }
        dailyTokenLimit = await setting("proactive_token_budget", default: 200_000)
        switch await setting("proactive_aggressiveness", default: "balanced") {
        case "relaxed": promotionBudget.maxPerHour = 2; nudgeCooldown = 40 * 60; dailyNudgeCap = 4
        case "eager": promotionBudget.maxPerHour = 8; nudgeCooldown = 10 * 60; dailyNudgeCap = 16
        default: promotionBudget.maxPerHour = 4; nudgeCooldown = 20 * 60; dailyNudgeCap = 8
        }
        heartbeatInterval = TimeInterval(await setting("heartbeat_interval_minutes", default: 10)) * 60
        await rolloverIfNeeded()
        await seedBuiltins()
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

    static func cronExpr(fromHHmm value: String) -> String? {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return "\(m) \(h) * * *"
    }

    // MARK: - Decision log

    private func decide(kind: String, source: String, triggerKey: String? = nil,
                        action: String, reason: String, payload: [String: String] = [:]) {
        let payloadJson = (try? String(decoding: JSONEncoder().encode(payload), as: UTF8.self)) ?? "{}"
        let row = DecisionRow(kind: kind, source: source, triggerKey: triggerKey,
                              action: action, reason: reason, payloadJson: payloadJson)
        Task { _ = try? await database.writer.write { db in try row.insert(db) } }
    }

    // MARK: - Trigger path

    /// External entry point: world syncs, context switches, meetings post here.
    func post(_ trigger: Trigger) {
        guard !muted else { return }
        switch admission.admit(trigger) {
        case .duplicate:
            decide(kind: "trigger", source: trigger.source, triggerKey: trigger.dedupeKey,
                   action: "deduped", reason: "duplicate within window")
            return
        case .rateLimited:
            decide(kind: "trigger", source: trigger.source, triggerKey: trigger.dedupeKey,
                   action: "rate_limited", reason: "source token bucket empty")
            return
        case .admitted:
            triggerQueue.append(trigger)
            pumpTriggers()
        }
    }

    func onContextSwitch(_ frame: CapturedFrame) {
        // Global 90s throttle BEFORE the pipeline: rapid app-hopping must cost
        // zero model calls and zero decision rows.
        guard Date.now.timeIntervalSince(lastSwitchEval) > 90 else { return }
        lastSwitchEval = .now
        let title = [frame.appName, frame.windowTitle].compactMap(\.self)
            .filter { !$0.isEmpty }.joined(separator: " — ")
        post(Trigger(source: "context_switch",
                     dedupeKey: "switch:\(frame.appBundleID ?? title)",
                     gateSummary: "User switched to: \(title.isEmpty ? "unknown app" : title)",
                     content: title))
    }

    private func pumpTriggers() {
        guard !pumping, !triggerQueue.isEmpty else { return }
        pumping = true
        let trigger = triggerQueue.removeFirst()
        Task {
            await process(trigger)
            pumping = false
            pumpTriggers()
        }
    }

    private func process(_ trigger: Trigger) async {
        let started = Date.now
        // Tiny on-device classifier sees the REDACTED summary only. No model
        // available → acknowledge (never silently lost, never promoted).
        let verdict: TriageAction
        var reason: String
        if let triage = await localFirst.generate(
            LocalTriage.self, instructions: Self.triageInstructions,
            prompt: "Event from \(trigger.source):\n\(trigger.gateSummary)"
        ) {
            verdict = TriageAction.parse(triage.action)
            reason = triage.reason
        } else {
            verdict = .acknowledge
            reason = "no triage model available"
        }
        let latency = Int(Date.now.timeIntervalSince(started) * 1000)

        switch GateDecision.from(verdict) {
        case .drop(let acknowledge):
            decide(kind: "trigger", source: trigger.source, triggerKey: trigger.dedupeKey,
                   action: acknowledge ? "acknowledged" : "dropped", reason: reason,
                   payload: ["latency_ms": "\(latency)"])
        case .promote(let escalated):
            guard hasBudget() else {
                decide(kind: "trigger", source: trigger.source, triggerKey: trigger.dedupeKey,
                       action: "budget_downgraded", reason: "daily token budget exhausted")
                return
            }
            guard promotionBudget.tryConsume() else {
                decide(kind: "trigger", source: trigger.source, triggerKey: trigger.dedupeKey,
                       action: "budget_downgraded", reason: "promotion budget exhausted (\(reason))")
                return
            }
            decide(kind: "trigger", source: trigger.source, triggerKey: trigger.dedupeKey,
                   action: escalated ? "escalated" : "reacted", reason: reason)
            // Full payload re-attached only past the gate (truncated).
            let prompt = """
            A background event needs handling. \(escalated ? "It was judged urgent." : "")
            Source: \(trigger.source)
            \(trigger.gateSummary)

            \(String(trigger.content.prefix(4000)))

            If there is something short and genuinely useful to tell the user, reply with it. \
            Otherwise reply with exactly: NOTHING.
            """
            let (text, usage) = await runBackground(
                prompt: prompt, kind: "trigger",
                label: "\(escalated ? "escalate" : "react"): \(trigger.source)",
                maxTurns: escalated ? 6 : 2)
            addBudget(usage.inputTokens + usage.outputTokens)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.uppercased().hasPrefix("NOTHING"), trimmed.count > 4 else { return }
            await maybeNudge(trimmed, source: trigger.source, dedupKey: trigger.dedupeKey,
                             context: trigger.gateSummary)
        }
    }

    // MARK: - Heartbeat (world-diff reflection)

    private func heartbeatTick() async {
        // Config is refreshed by the 30s cron loop; re-reading here would just
        // run seedBuiltins and the settings round-trips on a second schedule.
        guard !muted else { return }

        let checkpoint = await setting("mind_heartbeat_checkpoint", default: Date.distantPast)
        let diff = await worldDiff(since: checkpoint)
        await agent.cronStore.setHeartbeatRun(.now, result: diff == nil ? "quiet" : "reflected")
        try? await core.settings.set("mind_heartbeat_checkpoint", to: Date.now)

        guard let diff else {
            // Quiet tick: zero LLM calls. Logged so the feed shows the engine alive.
            decide(kind: "heartbeat", source: "worlds", action: "quiet", reason: "no world changes")
            return
        }
        guard hasBudget() else {
            decide(kind: "heartbeat", source: "worlds", action: "suppressed", reason: "daily token budget exhausted")
            return
        }

        let prompt = """
        It is \(Date.now.formatted(date: .complete, time: .shortened)). Since your last look, \
        the user's world changed:

        \(diff)

        Look through four lenses: Deadlines, Risks, Patterns, Opportunities. Most ticks the \
        right call is to do nothing — silence is the correct and common outcome. Do not invent busywork.
        """
        // API model when configured (can use read-only tools); on-device otherwise.
        var notify = ""
        var noteFacts: [String] = []
        var noteTasks: [String] = []
        if core.resolve(.brain) != nil {
            let (text, usage) = await runBackground(
                prompt: prompt + "\n\nIf something clears the bar, reply with one short message for the user. Otherwise reply with exactly: NOTHING.",
                kind: "heartbeat", label: "reflection", maxTurns: 6)
            addBudget(usage.inputTokens + usage.outputTokens)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !trimmed.uppercased().hasPrefix("NOTHING"), trimmed.count > 4 {
                notify = trimmed
            }
        } else if let reflection = await localFirst.generate(
            LocalReflection.self, instructions: Self.reflectionInstructions, prompt: prompt) {
            notify = reflection.notify.trimmingCharacters(in: .whitespacesAndNewlines)
            noteFacts = reflection.facts
            noteTasks = reflection.tasks
        }

        for fact in noteFacts.prefix(3) where !fact.trimmingCharacters(in: .whitespaces).isEmpty {
            await knowledge?.remember(fact)
            decide(kind: "reflection", source: "worlds", action: "noted_fact", reason: fact)
        }
        for task in noteTasks.prefix(3) where !task.trimmingCharacters(in: .whitespaces).isEmpty {
            await tasks.addTask(text: task, source: .chat, sourceID: nil)
            decide(kind: "reflection", source: "worlds", action: "task_added", reason: task)
        }
        if !notify.isEmpty, notify.uppercased() != "NOTHING" {
            await maybeNudge(notify, source: "reflection", dedupKey: "heartbeat", context: diff)
        } else if noteFacts.isEmpty, noteTasks.isEmpty {
            decide(kind: "reflection", source: "worlds", action: "quiet", reason: "nothing cleared the bar")
        }
    }

    /// Render what changed across worlds since the checkpoint, or nil when
    /// nothing did (the free quiet tick). Capped per world.
    private func worldDiff(since checkpoint: Date) async -> String? {
        let summary: [String] = (try? await database.reader.read { db -> [String] in
            var lines: [String] = []
            let runs = try Row.fetchAll(db, sql: """
                SELECT world_id, SUM(episodes_added) AS episodes, SUM(facts_added) AS facts,
                       SUM(entities_added) AS entities, SUM(edges_added) AS edges
                FROM ingest_run
                WHERE started_at > ? AND status IN ('done')
                GROUP BY world_id
                """, arguments: [checkpoint])
            for run in runs {
                let world: String = run["world_id"]
                let episodes: Int = run["episodes"] ?? 0
                let facts: Int = run["facts"] ?? 0
                if episodes + facts > 0 {
                    lines.append("- \(world): \(episodes) new items, \(facts) new facts")
                }
            }
            let facts = try Row.fetchAll(db, sql: """
                SELECT text FROM fact WHERE created_at > ? AND superseded_by IS NULL
                ORDER BY salience DESC, created_at DESC LIMIT 10
                """, arguments: [checkpoint])
            if !facts.isEmpty {
                lines.append("Recent facts learned:")
                for fact in facts { lines.append("  - \(fact["text"] as String)") }
            }
            let due = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM commitment WHERE status = 'open' AND due_at IS NOT NULL AND due_at < ?
                """, arguments: [Date.now.addingTimeInterval(3600)]) ?? 0
            if due > 0 { lines.append("- \(due) commitment(s) due within the hour") }
            return lines
        }) ?? []
        return summary.isEmpty ? nil : summary.joined(separator: "\n")
    }

    // MARK: - Staged delivery (60s, no LLM)

    private func deliveryTick() async {
        guard !muted else { return }
        var events: [DeliveryPlanner.Event] = []

        if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            let store = EKEventStore()
            let predicate = store.predicateForEvents(
                withStart: Date.now.addingTimeInterval(-600),
                end: Date.now.addingTimeInterval(3600), calendars: nil)
            for event in store.events(matching: predicate) where !event.isAllDay {
                guard let title = event.title, !title.isEmpty else { continue }
                events.append(DeliveryPlanner.Event(
                    category: "meeting",
                    overlapKey: "\(title)@\(Int(event.startDate.timeIntervalSince1970 / 300))",
                    title: title, at: event.startDate))
            }
        }
        for commitment in await tasks.dueCommitments(by: Date.now.addingTimeInterval(15 * 60)) {
            guard let due = commitment.dueAt else { continue }
            events.append(DeliveryPlanner.Event(
                category: "commitment", overlapKey: commitment.id,
                title: commitment.text, at: due))
        }

        for planned in DeliveryPlanner.plan(events: events) {
            // INSERT OR IGNORE on the stable key = fired at most once, ever.
            let inserted = (try? await database.writer.write { db -> Bool in
                try DeliveryStateRow(dedupeKey: planned.dedupeKey, category: planned.category,
                                     stage: planned.stage).insert(db, onConflict: .ignore)
                return db.changesCount > 0
            }) ?? false
            guard inserted else { continue }
            await deliver(title: planned.title, body: planned.body,
                          trigger: planned.category, dedupKey: planned.dedupeKey)
            decide(kind: "delivery", source: planned.category, triggerKey: planned.dedupeKey,
                   action: "notified", reason: "\(planned.stage): \(planned.body)")
            // Only the FINAL stage retires the commitment — dueCommitments
            // filters on status='open', so flipping at 'soon' would make the
            // 'due' escalation unreachable.
            if planned.category == "commitment", planned.stage == "due" {
                await tasks.setCommitmentStatus(planned.overlapKey, .notified)
            }
        }
        // Prune old sent-dedup rows + the decision ledger (feed shows 30 days).
        _ = try? await database.writer.write { db in
            try db.execute(sql: "DELETE FROM delivery_state WHERE sent_at < ?",
                           arguments: [Date.now.addingTimeInterval(-14 * 86400)])
            try db.execute(sql: "DELETE FROM decision WHERE ts < ?",
                           arguments: [Date.now.addingTimeInterval(-30 * 86400)])
        }
    }

    // MARK: - Cron + briefs (carried over)

    private func fireDueCron() async {
        for job in await agent.cronStore.dueJobs() {
            if job.id == Self.morningBriefID || job.id == Self.eveningRecapID {
                let text = await composeBrief(evening: job.id == Self.eveningRecapID)
                await agent.cronStore.markRan(id: job.id, status: text.isEmpty ? "empty" : "done")
                await deliver(title: job.name, body: text, trigger: "brief", dedupKey: nil)
                decide(kind: "delivery", source: "brief", action: "notified", reason: job.name)
                continue
            }
            guard hasBudget() else { continue }
            let (text, usage) = await runBackground(prompt: job.prompt, kind: "cron",
                                                    label: "cron: \(job.name)", maxTurns: 6)
            addBudget(usage.inputTokens + usage.outputTokens)
            await agent.cronStore.markRan(id: job.id, status: text.isEmpty ? "empty" : "done")
            await deliver(title: job.name, body: text, trigger: "cron", dedupKey: "cron:\(job.id)")
            decide(kind: "delivery", source: "cron", action: "notified", reason: job.name)
        }
    }

    private func composeBrief(evening: Bool) async -> String {
        let events = await todaysCalendarEvents()
        let openTasks = await tasks.tasks(statuses: [.open, .suggested])
        let dueToday = await tasks.dueCommitments(by: endOfToday())
        let mem = await knowledge?.context(for: evening ? "today's accomplishments" : "today's priorities") ?? ""

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
        return await localFirst.text(
            instructions: evening ? Self.recapInstructions : Self.briefInstructions,
            prompt: facts, maxTokens: 400) ?? facts
    }

    private func todaysCalendarEvents() async -> [String] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let store = EKEventStore()
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

    // MARK: - Nudge delivery (critic-gated, cooldown)

    /// Time-critical delivery categories exempt from nudge governance (a
    /// meeting reminder must fire even after five dismissed suggestions).
    private static let exemptTriggers = ["meeting", "commitment", "brief", "cron"]

    /// Final gate for agent-initiated messages, all DB-backed so it survives
    /// relaunch: daily cap → per-topic 24h dedup → cooldown scaled by recent
    /// dismissals (each dismissal in 48h quadruples it, capped 16x — the old
    /// funnel's backoff, derived from the nudge table instead of a setting) →
    /// CRITIC (most rejected). Every outcome is a decision row.
    private func maybeNudge(_ message: String, source: String, dedupKey: String?, context: String) async {
        struct Gate { var deliveredToday = 0; var lastAt: Date?; var topicRecent = false; var dismissals = 0 }
        let exempt = Self.exemptTriggers
        let key = dedupKey
        let gate: Gate = (try? await database.reader.read { db in
            var gate = Gate()
            let startOfDay = Calendar.current.startOfDay(for: .now)
            let placeholders = exempt.map { _ in "?" }.joined(separator: ",")
            gate.deliveredToday = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM nudge WHERE created_at >= ? AND trigger NOT IN (\(placeholders))
                """, arguments: StatementArguments([startOfDay] + exempt)) ?? 0
            gate.lastAt = try Date.fetchOne(db, sql: """
                SELECT MAX(created_at) FROM nudge WHERE trigger NOT IN (\(placeholders))
                """, arguments: StatementArguments(exempt))
            if let key {
                gate.topicRecent = try Int.fetchOne(db, sql: """
                    SELECT 1 FROM nudge WHERE dedup_key = ? AND created_at > ? LIMIT 1
                    """, arguments: [key, Date.now.addingTimeInterval(-86400)]) != nil
            }
            gate.dismissals = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM nudge WHERE state = 'dismissed' AND created_at > ?
                """, arguments: [Date.now.addingTimeInterval(-48 * 3600)]) ?? 0
            return gate
        }) ?? Gate()

        guard gate.deliveredToday < dailyNudgeCap else {
            decide(kind: "trigger", source: source, triggerKey: dedupKey,
                   action: "suppressed", reason: "daily nudge cap reached (\(dailyNudgeCap))")
            return
        }
        guard !gate.topicRecent else {
            decide(kind: "trigger", source: source, triggerKey: dedupKey,
                   action: "suppressed", reason: "same topic nudged within 24h")
            return
        }
        let multiplier = min(16.0, pow(4.0, Double(gate.dismissals)))
        let cooldown = nudgeCooldown * multiplier
        if let lastAt = gate.lastAt, Date.now.timeIntervalSince(lastAt) < cooldown {
            decide(kind: "trigger", source: source, triggerKey: dedupKey,
                   action: "suppressed",
                   reason: multiplier > 1 ? "backing off after \(gate.dismissals) recent dismissal(s)"
                                          : "nudge cooldown active")
            return
        }
        let verdict = await localFirst.generate(
            CriticVerdict.self, instructions: Self.criticInstructions,
            prompt: "Proposed message: \(message)\n\nContext:\n\(String(context.prefix(1500)))")
        guard verdict?.approve ?? false else {
            decide(kind: "trigger", source: source, triggerKey: dedupKey,
                   action: "suppressed", reason: "critic vetoed: \(message.prefix(120))")
            return
        }
        await deliver(title: "Jarvis", body: message, trigger: source, dedupKey: dedupKey)
        decide(kind: "trigger", source: source, triggerKey: dedupKey,
               action: "notified", reason: String(message.prefix(160)))
    }

    private func deliver(title: String, body: String, trigger: String, dedupKey: String?) async {
        let clean = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !muted else { return }
        _ = try? await database.writer.write { db in
            try NudgeRow(trigger: trigger, dedupKey: dedupKey, title: title, body: clean).insert(db)
        }
        notifications.post(title: title, body: clean)
        chat.receiveProactive(clean)
    }

    // MARK: - Background runs (carried over)

    private static let backgroundSystem = """
    You are Jarvis running a background task. Be concise. You may use read-only tools \
    to gather context. Produce a short, directly useful result for the user.
    """

    private func runBackground(prompt: String, kind: String, label: String, maxTurns: Int) async -> (String, Usage) {
        guard let resolved = core.resolve(.brain) else { return ("", Usage()) }
        let runID = UUID().uuidString
        let runStore = agent.runStore
        await runStore.createRun(id: runID, kind: kind, segmentID: nil, initiator: "jarvis", label: label)
        // Notch working status: show that Jarvis is working in the background, and
        // refine the label as each tool runs. Cleared on exit no matter how we return.
        chat.backgroundStatus = ChatStore.WorkingStatus(title: "Thinking", symbol: "sparkles")
        defer { chat.backgroundStatus = nil }
        let loop = AgentLoop(
            adapter: resolved.adapter, tools: agent.tools, gate: agent.gate,
            config: .init(model: resolved.model, system: Self.backgroundSystem, effort: resolved.effort,
                          maxTokens: 1500, maxTurns: maxTurns, isBackground: true)
        )
        var text = ""
        var usage = Usage()
        for await event in loop.run(initial: [.user(prompt)], runID: runID) {
            switch event {
            case .assistantMessage(let m) where !m.plainText.isEmpty: text = m.plainText
            case .toolCallStarted(let id, let name, let input):
                chat.backgroundStatus = ChatStore.activityLabel(forTool: name)
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

    // MARK: - Daily token budget (carried over)

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

    // MARK: - Prompts

    private static let triageInstructions = """
    You triage background events for a personal assistant. The event's content is \
    already indexed for memory either way — you only decide whether to ACT. Verdicts: \
    drop (irrelevant, routine, or noise — the most common answer), acknowledge (worth \
    marking as seen, no action), react (a quick background check would help), escalate \
    (genuinely urgent for the user right now — rare). Routine emails, app switches, and \
    ordinary activity are drop. When in doubt, drop.
    """
    private static let reflectionInstructions = """
    You reflect on recent changes in the user's world for a personal assistant. Look for \
    deadlines, risks, patterns, and opportunities. Most of the time nothing clears the bar — \
    empty results are the normal outcome. Never invent busywork. A notification must be \
    something the user would want to know right now.
    """
    private static let criticInstructions = """
    You are the last gate before Jarvis speaks up. Approve when the message tells the user \
    something genuinely useful, timely, or worth a quick heads-up that they'd be glad to see — \
    a real deadline, a helpful catch, a good opportunity. Reject only filler, the obvious, \
    or things that can clearly wait. Aim for a few good messages a day: noticeable but polite, \
    never chatty. When it's a close call and the message is genuinely helpful, approve it.
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
}
