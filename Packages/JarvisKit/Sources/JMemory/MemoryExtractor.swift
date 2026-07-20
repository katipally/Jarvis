import Foundation

/// Builds the extraction prompt and parses the aux model's JSON. The app makes
/// the actual model call (it owns the resolved provider); this keeps JMemory
/// free of networking.
public enum MemoryExtractor {
    public static let systemPrompt = """
    You extract durable memory from a conversation for a personal assistant. \
    Return ONLY a JSON object, no prose, with this shape:
    {
      "memories": [{"kind": "fact|preference|event|task|insight", "text": "...", "importance": 0.0-1.0}],
      "entities": [{"name": "...", "kind": "person|org|project|place|topic|artifact"}],
      "relations": [{"subject": "...", "relation": "snake_case_verb", "object": "..."}]
    }
    Rules: capture only lasting, user-specific information (facts about the user, \
    their preferences, ongoing projects, commitments) — never generic knowledge or \
    one-off chit-chat. Each memory is one concise THIRD-PERSON sentence ("User \
    prefers dark roast coffee") that will still be true weeks from now — never a \
    quote of what the user typed. NEVER extract greetings or mic tests ("hello", \
    "can you hear me"), questions the user asked, the fact that the user is talking \
    to an assistant, or transient machine state (open files, git status, what's on \
    screen). Use canonical entity names. Most conversations contain nothing worth \
    remembering — empty arrays are the normal result.
    """

    public static func userPrompt(conversation: String) -> String {
        "Extract memory from this conversation:\n\n\(conversation)"
    }

    /// Leniently parse a JSON object out of the model's response.
    public static func parse(_ response: String) -> ExtractionResult {
        guard let json = extractJSONObject(response),
              let data = json.data(using: .utf8) else {
            return ExtractionResult()
        }
        let decoder = JSONDecoder()
        if let result = try? decoder.decode(ExtractionResult.self, from: data) {
            return result
        }
        // Fall back to a tolerant manual decode (model may omit fields).
        return tolerantDecode(data) ?? ExtractionResult()
    }

    private static func extractJSONObject(_ text: String) -> String? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            return nil
        }
        return String(text[start...end])
    }

    private static func tolerantDecode(_ data: Data) -> ExtractionResult? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var result = ExtractionResult()
        for m in (obj["memories"] as? [[String: Any]]) ?? [] {
            guard let text = m["text"] as? String, !text.isEmpty else { continue }
            let kind = MemoryKind(rawValue: (m["kind"] as? String) ?? "fact") ?? .fact
            let importance = (m["importance"] as? Double) ?? 0.5
            result.memories.append(ExtractedMemory(kind: kind, text: text, importance: importance))
        }
        for e in (obj["entities"] as? [[String: Any]]) ?? [] {
            guard let name = e["name"] as? String, !name.isEmpty else { continue }
            result.entities.append(ExtractedEntity(name: name, kind: (e["kind"] as? String) ?? "topic"))
        }
        for r in (obj["relations"] as? [[String: Any]]) ?? [] {
            guard let s = r["subject"] as? String, let rel = r["relation"] as? String, let o = r["object"] as? String else { continue }
            result.relations.append(ExtractedRelation(subject: s, relation: rel, object: o))
        }
        return result
    }
}
