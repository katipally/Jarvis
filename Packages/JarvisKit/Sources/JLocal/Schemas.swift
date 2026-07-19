import Foundation
import FoundationModels

// @Generable DTOs for on-device guided generation. The model is forced to fill
// these shapes at the token level, so parsing never fails. All are value types
// of Sendable fields, so they cross the LocalModel actor boundary safely.

@Generable
public struct LocalMemory: Sendable {
    @Guide(description: "A lasting, user-specific fact worth remembering. Timeless, no dates. Under 15 words.")
    public var text: String
    @Guide(description: "One of: fact, preference, event, task, insight")
    public var kind: String
}

@Generable
public struct LocalEntity: Sendable {
    @Guide(description: "The canonical name of a person, place, project, org, or topic mentioned.")
    public var name: String
    @Guide(description: "One of: person, org, project, place, topic, artifact")
    public var kind: String
}

@Generable
public struct LocalRelation: Sendable {
    @Guide(description: "The entity the relation starts from (a name).")
    public var subject: String
    @Guide(description: "A short verb phrase, e.g. works_at, lives_in, prefers, uses.")
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

/// One structured extraction over a slice of conversation (or one sentence).
@Generable
public struct LocalExtraction: Sendable {
    @Guide(description: "Lasting facts about the user. Empty if the text is just chit-chat.")
    public var memories: [LocalMemory]
    @Guide(description: "Named entities mentioned. Empty if none.")
    public var entities: [LocalEntity]
    @Guide(description: "Relations between entities or between the user and an entity. Empty if none.")
    public var relations: [LocalRelation]
    @Guide(description: "Facts that are now false and should be retracted (free text). Empty if none.")
    public var invalidations: [String]
    @Guide(description: "Things the user committed to doing. Empty if none.")
    public var commitments: [LocalCommitment]
    @Guide(description: "Concrete action items or to-dos raised. Empty if none.")
    public var actionItems: [String]
}

/// GATE stage: should Jarvis interrupt at all? Default is no.
@Generable
public struct NudgeGate: Sendable {
    @Guide(description: "True ONLY for a concrete mistake, a time-sensitive action, or a non-obvious useful connection. Default false.")
    public var isRelevant: Bool
    @Guide(description: "One short reason for the decision.")
    public var reason: String
}

/// GENERATE stage: the nudge text, if any.
@Generable
public struct NudgeDraft: Sendable {
    @Guide(description: "One short helpful sentence, like a sharp friend texting. No greeting or filler.")
    public var message: String
    @Guide(description: "A short dedupe key for this topic, e.g. 'flight-conflict'.")
    public var topic: String
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
