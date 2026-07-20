import Foundation

// Relation vocabulary (Hive's model). The extractor emits free-text verbs, so
// "lives_in"/"resides_in"/"based_in" all mean the same thing — but supersession
// and contradiction detection only work if they compare equal. Every relation
// is normalized to a canonical verb at ingest, so a newer "resides_in" fact
// correctly supersedes an older "lives_in" one.
// ponytail: hand-curated synonym map — extend as real data shows gaps.
public enum Relations {
    static let synonyms: [String: String] = [
        // location (functional)
        "lives_in": "lives_in", "lives": "lives_in", "living_in": "lives_in",
        "resides_in": "lives_in", "resides": "lives_in", "based_in": "lives_in",
        "location": "lives_in", "from": "lives_in", "moved_to": "lives_in",
        // located_in stays distinct: places/events are located in places, people live in them
        "located_in": "located_in", "location_of": "located_in",
        // employment (functional)
        "works_at": "works_at", "works_for": "works_at", "employed_at": "works_at",
        "employed_by": "works_at", "job_at": "works_at", "works": "works_at", "employer": "works_at",
        // study (functional)
        "studies_at": "studies_at", "studied_at": "studies_at", "student_at": "studies_at",
        // relationships (functional)
        "dating": "dating", "dates": "dating", "partner_of": "dating", "seeing": "dating",
        "married_to": "married_to", "spouse_of": "married_to", "wife_of": "married_to", "husband_of": "married_to",
        "birthday_on": "birthday_on", "born_on": "birthday_on",
        // interests (non-functional — many at once)
        "likes": "likes", "loves": "likes", "enjoys": "likes", "into": "likes",
        "fan_of": "likes", "interested_in": "likes", "passionate_about": "likes", "prefers": "likes",
        "wants": "wants", "wants_to": "wants", "wishes_to": "wants", "planning_to": "wants", "hopes_to": "wants",
        "owns": "owns", "has": "owns",
        "knows": "knows", "friend_of": "knows", "friends_with": "knows", "met": "knows",
        "dislikes": "dislikes", "hates": "dislikes", "not_into": "dislikes",
        // family (functional-ish; not auto-superseded)
        "sibling_of": "sibling_of", "brother_of": "sibling_of", "sister_of": "sibling_of",
        "parent_of": "parent_of", "mother_of": "parent_of", "father_of": "parent_of",
        "child_of": "child_of", "son_of": "child_of", "daughter_of": "child_of",
        // skills / affiliations / work (non-functional)
        "plays": "plays", "practices": "plays",
        "speaks": "speaks",
        "member_of": "member_of", "volunteers_at": "member_of",
        "manages": "manages", "reports_to": "reports_to",
        "uses": "uses", "works_on": "works_on", "building": "works_on",
        "attends": "attends", "attending": "attends",
        "allergic_to": "allergic_to",
    ]

    /// Relations where a newer fact supersedes the old (moved cities, changed
    /// jobs). Keyed on CANONICAL verbs so paraphrases invalidate correctly.
    static let functional: Set<String> = [
        "lives_in", "works_at", "studies_at", "dating", "married_to", "birthday_on", "reports_to",
    ]

    public static func normalize(_ rel: String) -> String {
        let key = rel.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "[\\s-]+", with: "_", options: .regularExpression)
        return synonyms[key] ?? key
    }

    public static func isFunctional(_ canonicalRel: String) -> Bool {
        functional.contains(canonicalRel)
    }
}
