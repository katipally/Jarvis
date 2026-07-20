import Foundation
import GRDB
import JAgent
import JKnowledge
import JLocal
import JStore

/// Orchestrates the knowledge core. Conversation turns become EPISODES (the
/// provenance root shared with every other data source), which a debounced
/// on-device extraction turns into facts + graph writes. Also produces the
/// context block injected before each user turn, the durable `remember` path,
/// and the segment title/summary digest.
@MainActor
final class KnowledgeService {
    let core: JarvisCore
    let sessions: SessionManager
    let store: KnowledgeStore
    private let local: LocalFirst
    private let tasks: TaskStore
    private let database: JarvisDatabase
    /// Set by AppDelegate: new validated facts flow to the facet producers.
    var onFactsIngested: (@MainActor ([(id: String, text: String)]) -> Void)?

    init(core: JarvisCore, sessions: SessionManager, store: KnowledgeStore,
         local: LocalFirst, tasks: TaskStore, database: JarvisDatabase) {
        self.core = core
        self.sessions = sessions
        self.store = store
        self.local = local
        self.tasks = tasks
        self.database = database
    }

    // MARK: - Debounced extraction (Hive pattern)

    private var unextractedTurns = 0
    private var idleTask: Task<Void, Never>?
    private var extracting = false
    private var draining = false

    /// Called after each chat run. Fires extraction immediately once enough user
    /// turns have accumulated, otherwise on a rolling 45s idle timer.
    func turnCompleted() {
        unextractedTurns += 1
        idleTask?.cancel()
        if unextractedTurns >= 4 {
            idleTask = nil
            Task { await runExtraction() }
            return
        }
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled, let self else { return }
            self.idleTask = nil
            // Detached: a resuming turn's `idleTask?.cancel()` can't abort
            // these DB writes mid-extraction.
            Task { await self.runExtraction() }
        }
    }

    /// At launch: re-embed missing vectors, run the one-time fresh-start
    /// bootstrap (worlds + historical backfill), give failed episodes another
    /// chance, then resume the extraction queue.
    func bootSweep() async {
        await store.reembedMissing()
        await KnowledgeBootstrap.runIfNeeded(database: database, store: store, settings: core.settings)
        _ = try? await database.writer.write { db in
            try db.execute(sql: "UPDATE episode SET extraction_status = 'pending' WHERE extraction_status = 'failed'")
        }
        await runExtraction()
        Task { await drainPendingEpisodes() }
    }

    /// Pending (unextracted) user messages → one chat episode; the episode is
    /// the durable record, so messages are marked extracted only once it
    /// verifiably exists — LLM flakiness then only ever delays extraction,
    /// and a failed DB write leaves the messages pending for the next sweep.
    private func runExtraction() async {
        guard !extracting else {
            // A run is already processing a snapshot taken before these turns
            // landed; re-arm the idle fallback so they aren't stranded until
            // the next turn or boot.
            if idleTask == nil {
                idleTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(45))
                    guard !Task.isCancelled, let self else { return }
                    self.idleTask = nil
                    Task { await self.runExtraction() }
                }
            }
            return
        }
        extracting = true
        defer { extracting = false }

        let pending = await pendingUserMessages()
        unextractedTurns = 0
        guard !pending.isEmpty else { return }

        // Tool-result rows share role='user' but carry no prose — retire them.
        let empty = pending.filter { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !empty.isEmpty { await markExtracted(empty.map(\.id)) }

        let texts = pending.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !texts.isEmpty else { return }

        let conversation = texts.map(\.text).joined(separator: "\n")
        let episode: EpisodeRow?
        do {
            episode = try await store.addEpisode(
                worldId: "chat", externalId: "msgs:\(texts.first!.id)",
                occurredAt: .now, content: conversation
            )
        } catch {
            return // DB write failed — leave the messages pending, retry later
        }
        await markExtracted(texts.map(\.id)) // episode confirmed (or duplicate)
        guard let episode else { return }
        if await extractEpisode(episode) {
            await store.markEpisode(id: episode.id, status: "done")
        }
        // else: stays pending; drainPendingEpisodes retries later.
    }

    /// Gentle background drain of the episode queue (bootstrap backfill and any
    /// episodes whose extraction failed earlier). ~1 episode / 2s so a big
    /// history never pegs the ANE; caps per boot and resumes next launch.
    func drainPendingEpisodes(maxPerBoot: Int = 200) async {
        guard !draining else { return }
        draining = true
        defer { draining = false }
        var processed = 0
        while processed < maxPerBoot {
            guard let episode = await store.pendingEpisodes(limit: 1).first else { break }
            let ok = await extractEpisode(episode)
            await store.markEpisode(id: episode.id, status: ok ? "done" : "failed")
            processed += 1
            try? await Task.sleep(for: .seconds(2))
        }
    }

    // MARK: - Episode extraction

    /// On-device guided extraction (primary); aux/brain JSON fallback when the
    /// on-device model is off. Returns false when nothing produced a result.
    func extractEpisode(_ episode: EpisodeRow) async -> Bool {
        var produced = false
        var anyFailed = false
        for chunk in localChunks(episode.content, maxChars: 4000) {
            if let extraction = await local.generate(
                KnowledgeExtraction.self, instructions: Self.extractionInstructions,
                prompt: "Extract knowledge from:\n\n\(chunk)"
            ) {
                await ingest(extraction, episode: episode)
                produced = true
            } else {
                anyFailed = true
            }
        }
        // Partial success leaves the episode pending so a later sweep re-runs
        // the failed chunk; re-ingesting succeeded chunks is safe (store dedups).
        if produced { return !anyFailed }
        return await extractViaAPI(episode)
    }

    /// Map an on-device extraction into the store + task tables.
    private func ingest(_ extraction: KnowledgeExtraction, episode: EpisodeRow?) async {
        func salience(_ s: String) -> Double {
            switch s.lowercased() {
            case "high": 0.9
            case "low": 0.2
            default: 0.5
            }
        }
        let result = KnowledgeExtractionResult(
            facts: extraction.facts.map { ExtractedFact(text: $0.text, salience: salience($0.salience)) },
            entities: extraction.entities.map { ExtractedEntity(name: $0.name, type: EntityType.from($0.type)) },
            relations: extraction.relations.map { ExtractedRelation(subject: $0.subject, relation: $0.relation, object: $0.object) },
            invalidations: extraction.invalidations.map { ExtractedRelation(subject: $0.subject, relation: $0.relation, object: $0.object) }
        )
        await store.ingest(result, episode: episode)
        // Facet learning sees only facts that clear the same durability gate as
        // storage — raw extractor junk must not become 2x-weighted evidence.
        let validated = result.facts.filter { FactValidator.isDurable($0.text, source: episode?.content) }
        let refBase = episode?.id ?? UUID().uuidString
        onFactsIngested?(validated.enumerated().map { (id: "\(refBase):\($0.offset)", text: $0.element.text) })

        for c in extraction.commitments {
            let text = c.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            await tasks.addCommitment(text: text, dueAt: Self.parseDue(c.dueHint),
                                      dedupeKey: text.lowercased(), segmentID: nil)
        }
        for item in extraction.actionItems {
            let text = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            await tasks.addTask(text: text, source: .chat, sourceID: nil)
        }
    }

    // MARK: - API fallback (aux/brain JSON)

    private func extractViaAPI(_ episode: EpisodeRow) async -> Bool {
        guard let resolved = core.resolve(.aux) ?? core.resolve(.brain) else { return false }
        let request = ModelRequest(
            model: resolved.model, system: Self.jsonSystemPrompt,
            messages: [.user("Extract knowledge from:\n\n\(String(episode.content.prefix(12000)))")],
            maxTokens: 1024
        )
        let engine = ChatEngine(adapter: resolved.adapter)
        var response = ""
        var failed = false
        for await event in engine.run(request) {
            if case .assistantMessage(let m) = event { response = m.plainText }
            if case .failed = event { failed = true }
        }
        guard !failed, let result = Self.parseJSON(response) else { return false }
        await store.ingest(result, episode: episode)
        return true
    }

    /// Lenient JSON extraction: find the outermost object, tolerate fences.
    static func parseJSON(_ response: String) -> KnowledgeExtractionResult? {
        guard let start = response.firstIndex(of: "{"), let end = response.lastIndex(of: "}"),
              start < end,
              let data = String(response[start...end]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        func rel(_ d: [String: Any]) -> ExtractedRelation? {
            guard let s = d["subject"] as? String, let r = d["relation"] as? String else { return nil }
            return ExtractedRelation(subject: s, relation: r, object: d["object"] as? String ?? "")
        }
        let facts = (obj["facts"] as? [[String: Any]] ?? []).compactMap { d -> ExtractedFact? in
            guard let t = d["text"] as? String else { return nil }
            let s = d["salience"] as? String ?? "normal"
            return ExtractedFact(text: t, salience: s == "high" ? 0.9 : s == "low" ? 0.2 : 0.5)
        }
        let entities = (obj["entities"] as? [[String: Any]] ?? []).compactMap { d -> ExtractedEntity? in
            guard let n = d["name"] as? String else { return nil }
            return ExtractedEntity(name: n, type: EntityType.from(d["type"] as? String ?? "thing"))
        }
        return KnowledgeExtractionResult(
            facts: facts, entities: entities,
            relations: (obj["relations"] as? [[String: Any]] ?? []).compactMap(rel),
            invalidations: (obj["invalidations"] as? [[String: Any]] ?? []).compactMap(rel)
        )
    }

    // MARK: - Explicit remember

    /// Durable in-turn write for the `remember` tool: stores the fact
    /// immediately (bypassing the junk gate — a direct instruction wins) AND
    /// runs extraction on the sentence so entities/relations land in the graph.
    func remember(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await store.ingest(
            KnowledgeExtractionResult(facts: [ExtractedFact(text: trimmed, salience: 0.9)]),
            episode: nil, bypassValidation: true
        )
        if let extraction = await local.generate(
            KnowledgeExtraction.self, instructions: Self.extractionInstructions,
            prompt: "Extract knowledge from:\n\n\(trimmed)"
        ) {
            await ingest(extraction, episode: nil) // store dedups the duplicate fact
        }
    }

    // MARK: - Retrieval

    /// Context block for the user's message, or nil if nothing relevant.
    func context(for query: String) async -> String? {
        let facts = await store.retrieve(query: query, limit: 6)
        let graph = await store.graphContext(for: query, limit: 4)
        guard !facts.isEmpty || !graph.isEmpty else { return nil }

        var lines: [String] = []
        if !facts.isEmpty {
            lines.append("What you remember about the user:")
            lines.append(contentsOf: facts.map { "- \($0.text)" })
        }
        if !graph.isEmpty {
            lines.append("Related facts from the knowledge graph:")
            lines.append(contentsOf: graph.map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Segment digest (title + summary)

    /// On segment close: write a title/summary digest for the History list.
    func digestSegment(_ segmentID: String) async {
        let messages = await sessions.messages(inSegment: segmentID)
        let conversation = messages
            .filter { $0.role == .user || $0.role == .assistant }
            .map { "\($0.role == .user ? "User" : "Assistant"): \(text(of: $0))" }
            .joined(separator: "\n")
        guard conversation.count > 60 else {
            await sessions.setExtractionStatus(segmentID, "skipped")
            return
        }
        await sessions.setExtractionStatus(segmentID, "running")
        guard let digest = await local.generate(
            SegmentDigest.self, instructions: Self.digestInstructions,
            prompt: String(conversation.prefix(6000))
        ) else {
            await sessions.setExtractionStatus(segmentID, "skipped")
            return
        }
        await writeDigest(segmentID: segmentID, title: digest.title, summary: digest.summary)
        await sessions.setExtractionStatus(segmentID, "done")
    }

    private func writeDigest(segmentID: String, title: String, summary: String) async {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try? await database.writer.write { db in
            try db.execute(
                sql: "UPDATE segment SET title = COALESCE(title, NULLIF(?, '')), summary = ? WHERE id = ?",
                arguments: [t, s.isEmpty ? nil : s, segmentID]
            )
        }
    }

    // MARK: - Pending-message bookkeeping

    private func pendingUserMessages(limit: Int = 40) async -> [(id: String, text: String)] {
        (try? await database.reader.read { db -> [(id: String, text: String)] in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, content_json FROM message
                WHERE extracted_at IS NULL AND role = 'user' AND active = 1
                ORDER BY created_at LIMIT ?
                """, arguments: [limit])
            return rows.map { row in
                (id: row["id"] as String, text: plainText(row["content_json"] as String))
            }
        }) ?? []
    }

    private func markExtracted(_ ids: [String], now: Date = .now) async {
        guard !ids.isEmpty else { return }
        _ = try? await database.writer.write { db in
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            try db.execute(sql: "UPDATE message SET extracted_at = ? WHERE id IN (\(placeholders))",
                           arguments: StatementArguments([now] + ids))
        }
    }

    private func text(of message: SessionManager.StoredMessage) -> String {
        message.content.compactMap { if case .text(let t) = $0 { return t } else { return nil } }.joined()
    }

    // MARK: - Prompts

    static let extractionInstructions = """
    You extract durable knowledge from text for a personal assistant. Facts must be \
    (1) lasting — still true and useful weeks from now, (2) third person, using "Me" \
    for the user ("Me prefers dark roast coffee"), (3) a distillation — never a quote. \
    Entities are named things (people, orgs, places, events, topics, projects). \
    Relations link entities with short snake_case verbs (Me works_at Acme, \
    Me lives_in Denver). Report invalidations when something stopped being true \
    (quit a job, moved away). NEVER extract: greetings or mic tests, questions, the \
    fact that someone is talking to an assistant, transient machine state, or anything \
    about the conversation itself. Most text contains nothing worth keeping — empty \
    arrays are the normal result.
    """

    private static let jsonSystemPrompt = """
    Extract durable knowledge from the text as strict JSON, no prose:
    {"facts":[{"text":"...","salience":"high|normal|low"}],
     "entities":[{"name":"...","type":"person|org|place|event|topic|project|thing"}],
     "relations":[{"subject":"...","relation":"snake_case_verb","object":"..."}],
     "invalidations":[{"subject":"...","relation":"...","object":""}]}
    Facts are lasting, third-person, use "Me" for the user, never quotes or transient \
    state. Empty arrays are the normal result.
    """

    private static let digestInstructions = """
    Summarize a finished conversation for a history list: a short Title Case title \
    (at most 8 words) and a one or two sentence summary of what was discussed.
    """

    /// Best-effort natural-language date from a hint like "Friday" or "today 3pm".
    private static func parseDue(_ hint: String) -> Date? {
        let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return detector.firstMatch(in: trimmed, range: range)?.date
    }
}
