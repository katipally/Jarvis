import Foundation
import FoundationModels

// @Generable DTOs for on-device guided generation. The model is forced to fill
// these shapes at the token level, so parsing never fails. All are value types
// of Sendable fields, so they cross the LocalModel actor boundary safely.

@Generable
public struct LocalFact: Sendable {
    @Guide(description: "A lasting, user-specific fact in third person, e.g. 'Me prefers dark roast coffee'. Timeless, under 15 words. Never a greeting, question, quote of the user's words, or transient machine state.")
    public var text: String
    @Guide(description: "One of: high, normal, low — how much this fact matters long-term.")
    public var salience: String
}

@Generable
public struct LocalEntity: Sendable {
    @Guide(description: "The canonical name of a named thing mentioned. Use 'Me' for the user.")
    public var name: String
    @Guide(description: "One of: person, org, place, event, topic, project, thing")
    public var type: String
}

@Generable
public struct LocalRelation: Sendable {
    @Guide(description: "The entity the relation starts from (a name). Use 'Me' for the user.")
    public var subject: String
    @Guide(description: "A short snake_case verb, e.g. works_at, lives_in, likes, uses, knows.")
    public var relation: String
    @Guide(description: "The entity or value the relation points to.")
    public var object: String
}

@Generable
public struct LocalCommitment: Sendable {
    @Guide(description: "Something the user said they will do, in their words. Under 20 words.")
    public var text: String
    @Guide(description: "When it's due if stated, e.g. 'today 3pm', 'Friday', 'end of week'. Empty if none.")
    public var dueHint: String
}

/// One structured extraction over an episode (a slice of conversation, an
/// email, a note…). The v0.4 knowledge-core contract.
@Generable
public struct KnowledgeExtraction: Sendable {
    @Guide(description: "Durable third-person facts about the user or people/places/projects in their life. Empty is the normal result — greetings, questions, tests, and transient state yield nothing.")
    public var facts: [LocalFact]
    @Guide(description: "Named things mentioned. Empty if none.")
    public var entities: [LocalEntity]
    @Guide(description: "Links between entities, e.g. Me works_at Acme. Empty if none.")
    public var relations: [LocalRelation]
    @Guide(description: "Relations that are no longer true (quit, moved away, broke up). Object may be empty. Empty if none.")
    public var invalidations: [LocalRelation]
    @Guide(description: "Things the user committed to doing. Empty if none.")
    public var commitments: [LocalCommitment]
    @Guide(description: "Concrete action items or to-dos raised. Empty if none.")
    public var actionItems: [String]
}

/// Trigger triage (openhuman trigger_triage): 4-way verdict, bias to drop.
@Generable
public struct LocalTriage: Sendable {
    @Guide(description: "One of: drop, acknowledge, react, escalate. Most events deserve drop. acknowledge = worth remembering but no action. react = a quick background action helps. escalate = genuinely urgent for the user right now. When in doubt, drop — over-escalating wastes attention.")
    public var action: String
    @Guide(description: "One short reason for the verdict.")
    public var reason: String
}

/// Heartbeat reflection over a world diff. Silence is the correct and common
/// outcome — most ticks produce nothing.
@Generable
public struct LocalReflection: Sendable {
    @Guide(description: "One short, genuinely useful message for the user, or empty. High bar: a real deadline, a risk, a pattern they'd want to know now. Empty is the normal result.")
    public var notify: String
    @Guide(description: "Durable facts worth noting from the changes. Empty is normal.")
    public var facts: [String]
    @Guide(description: "Concrete tasks to add to the user's list. Empty is normal.")
    public var tasks: [String]
}

/// CRITIC stage: last gate before delivery. Most drafts should be rejected.
@Generable
public struct CriticVerdict: Sendable {
    @Guide(description: "True only if this genuinely tells the user something new and useful they don't already know. Default false.")
    public var approve: Bool
}

/// Title + summary for a closed conversation segment.
@Generable
public struct SegmentDigest: Sendable {
    @Guide(description: "A concise Title Case title, at most 8 words.")
    public var title: String
    @Guide(description: "A one or two sentence summary of what the conversation covered.")
    public var summary: String
}

/// Structured summary of a finished meeting.
@Generable
public struct MeetingSummary: Sendable {
    @Guide(description: "A concise Title Case title for the meeting, at most 8 words.")
    public var title: String
    @Guide(description: "A short paragraph overview of what was discussed and decided.")
    public var overview: String
    @Guide(description: "Concrete action items with owners if stated. Empty if none.")
    public var actionItems: [String]
    @Guide(description: "Durable facts about the user or their world worth remembering. Empty if none.")
    public var keyFacts: [String]
}
