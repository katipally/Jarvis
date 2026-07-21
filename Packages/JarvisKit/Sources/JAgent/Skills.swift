import Foundation

/// A named capability hint, authored in `skills.md` and injected into a turn
/// when it looks relevant. Keeping skills as DATA (not prose baked into the
/// system prompt) means the catalog grows by editing markdown, not code — and
/// only the skills a turn actually needs ride along, keeping the prompt small.
public struct Skill: Sendable, Equatable {
    public let name: String
    /// Lowercased keywords; the skill is selected when any appears in the turn.
    public let triggers: [String]
    public let body: String

    public init(name: String, triggers: [String], body: String) {
        self.name = name
        self.triggers = triggers
        self.body = body
    }
}

/// An immutable set of skills, parsed from a markdown catalog and selected per
/// turn by keyword match.
public struct SkillRegistry: Sendable {
    public let skills: [Skill]

    public init(_ skills: [Skill]) { self.skills = skills }

    /// Parse a `skills.md` document. Each skill is a `## Name` heading, an
    /// optional `triggers: a, b, c` line, then the body (everything up to the
    /// next `## ` heading). Text before the first `## ` heading is ignored, so
    /// the file can open with a `#` title and notes.
    public init(markdown: String) {
        var parsed: [Skill] = []
        var name: String?
        var triggers: [String] = []
        var body: [String] = []

        func flush() {
            if let name {
                let text = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { parsed.append(Skill(name: name, triggers: triggers, body: text)) }
            }
            name = nil
            triggers = []
            body = []
        }

        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("## ") {
                flush()
                name = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
            } else if name != nil, line.lowercased().hasPrefix("triggers:") {
                triggers = line.dropFirst("triggers:".count)
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                    .filter { !$0.isEmpty }
            } else if name != nil {
                body.append(line)
            }
        }
        flush()
        self.init(parsed)
    }

    public var isEmpty: Bool { skills.isEmpty }

    /// Skills whose triggers appear (case-insensitive substring) in the text.
    /// A skill with no triggers is dormant — never auto-selected.
    public func selected(for text: String) -> [Skill] {
        let hay = text.lowercased()
        return skills.filter { skill in
            skill.triggers.contains { hay.contains($0) }
        }
    }

    /// A prompt block of the skills relevant to this turn, or nil if none match.
    /// Injected into the per-turn context (not the static system prompt) so the
    /// provider prompt cache stays warm across turns.
    public func promptBlock(for text: String) -> String? {
        let hits = selected(for: text)
        guard !hits.isEmpty else { return nil }
        return hits.map { "## \($0.name)\n\($0.body)" }.joined(separator: "\n\n")
    }
}
