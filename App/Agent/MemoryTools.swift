import Foundation
import JAgent
import JKnowledge

/// In-turn memory: explicit writes ("remember that…") and recall search.
/// Both auto-run — they touch only Jarvis's local knowledge store.
enum MemoryTools {
    /// Pass `knowledge` so `remember` grows the graph (entities/relations) too;
    /// without it, remember still writes the plain fact row.
    static func registry(store: KnowledgeStore, knowledge: KnowledgeService? = nil) -> [ToolSpec] {
        [remember(store, knowledge), searchMemory(store)]
    }

    private static func remember(_ store: KnowledgeStore, _ knowledge: KnowledgeService?) -> ToolSpec {
        ToolSpec(
            name: "remember",
            description: "Save a fact durably to long-term memory, effective immediately. Use when the user says 'remember…', states a lasting preference, or shares a fact about themselves worth keeping. Store one self-contained sentence.",
            parameters: obj([p("text", "The fact to remember, as one self-contained sentence, e.g. 'The user's garage code is 1234'")],
                            required: ["text"]),
            tier: .readOnly
        ) { input, _ in
            guard let text = str(input, "text") else { return ToolOutput("Missing 'text'.", isError: true) }
            if let knowledge {
                await knowledge.remember(text)
            } else {
                await store.ingest(
                    KnowledgeExtractionResult(facts: [ExtractedFact(text: text, salience: 0.9)]),
                    episode: nil, bypassValidation: true
                )
            }
            return ToolOutput("Remembered.")
        }
    }

    private static func searchMemory(_ store: KnowledgeStore) -> ToolSpec {
        ToolSpec(
            name: "search_memory",
            description: "Search long-term memory (facts, preferences, past events) beyond what the <context> block already surfaced. Use when the user asks what you know or refers to something from an earlier conversation.",
            parameters: obj([p("query", "What to search memory for")], required: ["query"]),
            tier: .readOnly
        ) { input, _ in
            guard let query = str(input, "query") else { return ToolOutput("Missing 'query'.", isError: true) }
            let facts = await store.retrieve(query: query, limit: 10)
            let graph = await store.graphContext(for: query, limit: 6)
            if facts.isEmpty && graph.isEmpty { return ToolOutput("Nothing relevant in memory.") }
            var lines = facts.map { "- \($0.text)" }
            lines.append(contentsOf: graph.map { "- \($0)" })
            return ToolOutput(lines.joined(separator: "\n"))
        }
    }
}
