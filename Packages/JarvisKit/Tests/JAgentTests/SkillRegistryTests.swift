import Testing
@testable import JAgent

struct SkillRegistryTests {
    private let markdown = """
    # Skills
    intro text before the first heading is ignored

    ## Alpha
    triggers: foo, Bar Baz
    Do the alpha thing.

    ## Beta
    triggers: qux
    Line one.
    Line two.

    ## Dormant
    No triggers, so never selected.
    """

    @Test func parsesHeadingsTriggersAndBody() {
        let reg = SkillRegistry(markdown: markdown)
        #expect(reg.skills.count == 3)
        #expect(reg.skills[0].name == "Alpha")
        #expect(reg.skills[0].triggers == ["foo", "bar baz"]) // lowercased, trimmed
        #expect(reg.skills[1].body == "Line one.\nLine two.") // multi-line body preserved
        #expect(reg.skills[2].triggers.isEmpty)
    }

    @Test func selectsByCaseInsensitiveSubstring() {
        let reg = SkillRegistry(markdown: markdown)
        #expect(reg.selected(for: "please FOO it").map(\.name) == ["Alpha"])
        #expect(reg.selected(for: "bar baz now").map(\.name) == ["Alpha"])
        #expect(reg.selected(for: "qux").map(\.name) == ["Beta"])
        #expect(reg.selected(for: "nothing relevant").isEmpty) // dormant never matches
    }

    @Test func promptBlockIsNilWhenNothingMatches() {
        let reg = SkillRegistry(markdown: markdown)
        #expect(reg.promptBlock(for: "no match here") == nil)
        #expect(reg.promptBlock(for: "foo")?.contains("Do the alpha thing.") == true)
    }
}
