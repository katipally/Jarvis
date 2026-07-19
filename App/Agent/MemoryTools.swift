import Foundation
import JAgent
import JMemory

/// In-turn memory: explicit writes ("remember that…") and recall search.
/// Both auto-run — they touch only Jarvis's local memory store.
enum MemoryTools {
    static func registry(store: MemoryStore) -> [ToolSpec] {
        [remember(store), searchMemory(store)]
    }

    private static func remember(_ store: MemoryStore) -> ToolSpec {
        ToolSpec(
            name: "remember",
            description: "Save a fact durably to long-term memory, effective immediately. Use when the user says 'remember…', states a lasting preference, or shares a fact about themselves worth keeping. Store one self-contained sentence.",
            parameters: obj([p("text", "The fact to remember, as one self-contained sentence, e.g. 'The user's garage code is 1234'"),
                             pEnum("kind", "What kind of memory this is", MemoryKind.allCases.map(\.rawValue))],
                            required: ["text"]),
            tier: .readOnly
        ) { input, _ in
            guard let text = str(input, "text") else { return ToolOutput("Missing 'text'.", isError: true) }
            let kind = str(input, "kind").flatMap(MemoryKind.init(rawValue:)) ?? .fact
            let result = ExtractionResult(memories: [ExtractedMemory(kind: kind, text: text, importance: 0.8)])
            await store.ingest(result, segmentID: nil)
            return ToolOutput("Remembered.")
        }
    }

    private static func searchMemory(_ store: MemoryStore) -> ToolSpec {
        ToolSpec(
            name: "search_memory",
            description: "Search long-term memory (facts, preferences, past events) beyond what the <context> block already surfaced. Use when the user asks what you know or refers to something from an earlier conversation.",
            parameters: obj([p("query", "What to search memory for")], required: ["query"]),
            tier: .readOnly
        ) { input, _ in
            guard let query = str(input, "query") else { return ToolOutput("Missing 'query'.", isError: true) }
            let memories = await store.retrieve(query: query, limit: 10)
            let graph = await store.graphContext(for: query, limit: 6)
            if memories.isEmpty && graph.isEmpty { return ToolOutput("Nothing relevant in memory.") }
            var lines = memories.map { "- \($0.text)" }
            lines.append(contentsOf: graph.map { "- \($0)" })
            return ToolOutput(lines.joined(separator: "\n"))
        }
    }
}
