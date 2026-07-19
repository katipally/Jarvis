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
            guard !Task.isCancelled else { return }
            await self?.runExtraction()
        }
    }

    /// At launch: re-embed anything missing a current-model vector, then resume
    /// extraction for user messages a previous run never processed.
    func bootSweep() async {
        await store.reembedMissing()
        await runExtraction()
    }

    /// Extract from all pending (unextracted) user messages, then mark them done
    /// on success. On failure the rows stay pending for the next sweep/turn.
    private func runExtraction() async {
        guard !extracting else { return }
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
        for chunk in localChunks(conversation, maxChars: 4000) {
            if let extraction = await local.generate(
                LocalExtraction.self, instructions: Self.extractionInstructions,
                prompt: Self.extractionPrompt(chunk)
            ) {
                await ingest(extraction, segmentID: segmentID)
                produced = true
            }
        }
        if produced { return true }

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
        await store.ingest(MemoryExtractor.parse(response), segmentID: segmentID)
        return true
    }

    /// Map an on-device extraction into the store + task tables.
    private func ingest(_ extraction: LocalExtraction, segmentID: String?) async {
        let result = ExtractionResult(
            memories: extraction.memories.compactMap { m in
                let t = m.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return nil }
                return ExtractedMemory(kind: MemoryKind(rawValue: m.kind.lowercased()) ?? .fact, text: t)
            },
            entities: extraction.entities.compactMap { e in
                let n = e.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !n.isEmpty else { return nil }
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
    personal assistant. Capture only lasting facts about the user, their preferences, \
    ongoing projects, the entities they mention, relations involving them, commitments \
    they make, and concrete action items. Ignore chit-chat and generic world knowledge. \
    If nothing is worth keeping, return empty arrays.
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
