import JAgent
import JMemory
import JStore

/// Orchestrates memory: extracts on segment close (aux model) and produces the
/// context block injected before each user turn.
@MainActor
final class MemoryService {
    let core: JarvisCore
    let sessions: SessionManager
    let store: MemoryStore

    init(core: JarvisCore, sessions: SessionManager, store: MemoryStore) {
        self.core = core
        self.sessions = sessions
        self.store = store
    }

    /// Extract durable memory from a just-closed segment.
    func extract(segmentID: String) async {
        let messages = await sessions.messages(inSegment: segmentID)
        let conversation = messages
            .filter { $0.role == .user || $0.role == .assistant }
            .map { "\($0.role == .user ? "User" : "Assistant"): \(text(of: $0))" }
            .joined(separator: "\n")
        guard conversation.count > 60 else { return } // too short to be worth it

        guard let resolved = core.resolve(.aux) ?? core.resolve(.brain) else { return }
        await sessions.setExtractionStatus(segmentID, "running")

        let request = ModelRequest(
            model: resolved.model,
            system: MemoryExtractor.systemPrompt,
            messages: [.user(MemoryExtractor.userPrompt(conversation: conversation))],
            maxTokens: 1024
        )
        let engine = ChatEngine(adapter: resolved.adapter)
        var response = ""
        for await event in engine.run(request) {
            if case .assistantMessage(let message) = event { response = message.plainText }
            if case .failed = event {
                await sessions.setExtractionStatus(segmentID, "failed")
                return
            }
        }

        let result = MemoryExtractor.parse(response)
        await store.ingest(result, segmentID: segmentID)
        await store.consolidate(olderThan: 0)
        await sessions.setExtractionStatus(segmentID, "done")
    }

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

    private func text(of message: SessionManager.StoredMessage) -> String {
        message.content.compactMap { if case .text(let t) = $0 { return t } else { return nil } }.joined()
    }
}
