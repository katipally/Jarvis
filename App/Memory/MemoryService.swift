import Foundation
import GRDB
import JAgent
import JLocal
import JMemory
import JStore

/// Orchestrates memory. Extraction is DEBOUNCED (Hive pattern): it fires after a
/// few user turns or a short idle, reading the user's own words (not assistant
/// prose, to avoid hallucinated facts), and marks each message extracted so a
/// boot sweep can resume anything left pending. Segment close now writes a
/// title/summary digest instead of triggering extraction. Also produces the
/// context block injected before each user turn, and the durable `remember` path.
@MainActor
final class MemoryService {
    let core: JarvisCore
    let sessions: SessionManager
    let store: MemoryStore
    private let local: LocalFirst
    private let tasks: TaskStore
    private let database: JarvisDatabase

    init(core: JarvisCore, sessions: SessionManager, store: MemoryStore,
         local: LocalFirst, tasks: TaskStore, database: JarvisDatabase) {
        self.core = core
        self.sessions = sessions
        self.store = store
        self.local = local
        self.tasks = tasks
        self.database = database
    }

    // MARK: - Debounced extraction

    private var unextractedTurns = 0
    private var idleTask: Task<Void, Never>?
    private var extracting = false

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
            // Detached: a resuming turn's `idleTask?.cancel()` (now targeting a
            // new idle task) can't abort these DB writes mid-extraction.
            Task { await self.runExtraction() }
        }
    }

    /// At launch: re-embed anything missing a current-model vector, archive any
    /// stored memories that fail the durability validator (junk saved before
    /// the filter existed — archived, not deleted, so it's recoverable), then
    /// resume extraction for user messages a previous run never processed.
    func bootSweep() async {
        await store.reembedMissing()
        for item in await store.list() where !MemoryValidator.isDurable(item.text) {
            await store.archive(id: item.id)
        }
        await runExtraction()
    }

    /// Extract from all pending (unextracted) user messages, then mark them done
    /// on success. On failure the rows stay pending for the next sweep/turn.
    private func runExtraction() async {
        guard !extracting else {
            // A run is already processing a snapshot taken before these turns
            // landed; re-arm the idle fallback so they aren't stranded until the
            // next turn or bootSweep. Detached extraction (as in turnCompleted)
            // keeps a later `idleTask?.cancel()` from aborting writes.
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

        // Tool-result rows share role='user' but carry no prose — retire them so
        // they don't re-trigger every sweep.
        let empty = pending.filter { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !empty.isEmpty { await markExtracted(empty.map(\.id)) }

        let texts = pending.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !texts.isEmpty else { return }

        let conversation = texts.map(\.text).joined(separator: "\n")
        if await extractAndIngest(conversation, segmentID: nil) {
            await markExtracted(texts.map(\.id))
        }
    }

    /// On-device guided extraction (primary); aux/brain JSON extraction fallback
    /// when the on-device model is off. Returns false only when nothing produced
    /// a result, so the caller leaves the rows pending for a retry.
    private func extractAndIngest(_ conversation: String, segmentID: String?) async -> Bool {
        var produced = false
        var anyFailed = false
        for chunk in localChunks(conversation, maxChars: 4000) {
            if let extraction = await local.generate(
                LocalExtraction.self, instructions: Self.extractionInstructions,
                prompt: Self.extractionPrompt(chunk)
            ) {
                await ingest(extraction, segmentID: segmentID, source: chunk)
                produced = true
            } else {
                anyFailed = true
            }
        }
        // Only report done when every chunk produced output; a partial success
        // leaves the rows pending so a later sweep re-extracts the failed chunk.
        // Re-ingesting the succeeded chunks then is safe — the store dedups.
        if produced { return !anyFailed }

        // Fallback: aux/brain JSON path (memories/entities/relations only).
        guard let resolved = core.resolve(.aux) ?? core.resolve(.brain) else { return false }
        let request = ModelRequest(
            model: resolved.model, system: MemoryExtractor.systemPrompt,
            messages: [.user(MemoryExtractor.userPrompt(conversation: conversation))], maxTokens: 1024
        )
        let engine = ChatEngine(adapter: resolved.adapter)
        var response = ""
        var failed = false
        for await event in engine.run(request) {
            if case .assistantMessage(let m) = event { response = m.plainText }
            if case .failed = event { failed = true }
        }
        guard !failed else { return false }
        var parsed = MemoryExtractor.parse(response)
        // Model-extracted memories must clear the durability gate on this path too.
        parsed.memories = parsed.memories.filter { MemoryValidator.isDurable($0.text, source: conversation) }
        parsed.entities = parsed.entities.filter { MemoryValidator.isRealEntity($0.name) }
        await store.ingest(parsed, segmentID: segmentID)
        return true
    }

    /// Map an on-device extraction into the store + task tables. `source` is the
    /// conversation the extraction came from — memories that fail the durability
    /// validator (chit-chat echoes, meta observations, transient state) are
    /// dropped here, before they ever reach the store.
    private func ingest(_ extraction: LocalExtraction, segmentID: String?, source: String? = nil) async {
        let result = ExtractionResult(
            memories: extraction.memories.compactMap { m in
                let t = m.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty, MemoryValidator.isDurable(t, source: source) else { return nil }
                return ExtractedMemory(kind: MemoryKind(rawValue: m.kind.lowercased()) ?? .fact, text: t)
            },
            entities: extraction.entities.compactMap { e in
                let n = e.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !n.isEmpty, MemoryValidator.isRealEntity(n) else { return nil }
                return ExtractedEntity(name: n, kind: e.kind.lowercased())
            },
            relations: extraction.relations.compactMap { r in
                let s = r.subject.trimmingCharacters(in: .whitespacesAndNewlines)
                let o = r.object.trimmingCharacters(in: .whitespacesAndNewlines)
                let rel = r.relation.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: " ", with: "_")
                guard !s.isEmpty, !o.isEmpty, !rel.isEmpty else { return nil }
                return ExtractedRelation(subject: s, relation: rel, object: o)
            }
        )
        await store.ingest(result, segmentID: segmentID)
        await store.supersede(matching: extraction.invalidations)

        for c in extraction.commitments {
            let text = c.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            await tasks.addCommitment(text: text, dueAt: Self.parseDue(c.dueHint),
                                      dedupeKey: text.lowercased(), segmentID: segmentID)
        }
        for item in extraction.actionItems {
            let text = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            await tasks.addTask(text: text, source: .chat, sourceID: segmentID)
        }
    }

    // MARK: - Segment digest (title + summary)

    /// On segment close: write a title/summary digest for the History list.
    /// (Durable-memory extraction now runs continuously, not here.)
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
            // Keep a user-set title; only fill an empty one from the digest.
            try db.execute(
                sql: "UPDATE segment SET title = COALESCE(title, NULLIF(?, '')), summary = ? WHERE id = ?",
                arguments: [t, s.isEmpty ? nil : s, segmentID]
            )
        }
    }

    // MARK: - Explicit remember

    /// Durable in-turn memory write for the `remember` tool. Adds the explicit
    /// memory immediately AND runs extraction on the sentence so entities and
    /// relations land in the graph, not just a memory row.
    func remember(_ text: String, kind: MemoryKind = .fact) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await store.ingest(
            ExtractionResult(memories: [ExtractedMemory(kind: kind, text: trimmed, importance: 0.8)]),
            segmentID: nil
        )
        if let extraction = await local.generate(
            LocalExtraction.self, instructions: Self.extractionInstructions,
            prompt: Self.extractionPrompt(trimmed)
        ) {
            // dedup in the store drops the duplicate memory; graph/commitments land.
            await ingest(extraction, segmentID: nil)
        }
    }

    // MARK: - Retrieval

    /// Retrieve a context block for the user's message, or nil if nothing relevant.
    func context(for query: String) async -> String? {
        let memories = await store.retrieve(query: query, limit: 6)
        let graph = await store.graphContext(for: query, limit: 4)
        guard !memories.isEmpty || !graph.isEmpty else { return nil }
        await store.touch(ids: memories.map(\.id))

        var lines: [String] = []
        if !memories.isEmpty {
            lines.append("What you remember about the user:")
            lines.append(contentsOf: memories.map { "- \($0.text)" })
        }
        if !graph.isEmpty {
            lines.append("Related facts from the knowledge graph:")
            lines.append(contentsOf: graph.map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Pending-message bookkeeping

    /// Unextracted user messages (partial index `message_pending_extraction`),
    /// oldest first, paired with their plain text.
    private func pendingUserMessages(limit: Int = 40) async -> [(id: String, text: String)] {
        (try? await database.reader.read { db -> [(id: String, text: String)] in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, content_json FROM message
                WHERE extracted_at IS NULL AND role = 'user' AND active = 1
                ORDER BY created_at LIMIT ?
                """, arguments: [limit])
            return rows.map { row in
                let id: String = row["id"]
                let json: String = row["content_json"]
                let text = decodeContent(json)
                    .compactMap { if case .text(let t) = $0 { t } else { nil } }
                    .joined()
                return (id: id, text: text)
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

    // MARK: - Prompts / parsing

    private static let extractionInstructions = """
    You extract durable, user-specific memory from the user's own messages for a \
    personal assistant. A memory must be (1) a lasting fact that will still be true \
    and useful weeks from now, (2) written in third person ("User prefers dark roast \
    coffee"), (3) a distillation — never a quote or restatement of what the user typed. \
    NEVER extract: greetings or mic tests ("hello", "can you hear me"), questions the \
    user asked, the fact that the user is talking to an assistant, transient machine \
    state (open files, git status, what's on screen), or anything about this \
    conversation itself. Most messages contain nothing worth keeping — empty arrays \
    are the normal result.
    """

    private static func extractionPrompt(_ text: String) -> String {
        "Extract memory from the user's words:\n\n\(text)"
    }

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
