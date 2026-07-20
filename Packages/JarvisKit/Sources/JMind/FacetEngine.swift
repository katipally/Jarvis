import Foundation

// Faithful port of openhuman's learning/stability_detector.rs: user-preference
// facets earn a stability score from recency-decayed evidence, promote into
// the prompt when stable, and decay out when reinforcement stops.
//
//   stability = Σ_families( weight(cue) × exp(-Δt/half_life(class)) × ln(1+count) )
//               × explicit_mult × user_state_mult
//
// explicit_mult = 2.0 when any evidence is Explicit; pinned → ∞, forgotten → 0.

public enum FacetClass: String, Sendable, CaseIterable, Codable {
    case identity, veto, tooling, goal, style, channel

    /// Per-class half-life (seconds).
    public var halfLife: TimeInterval {
        switch self {
        case .identity: 90 * 86400
        case .veto: 60 * 86400
        case .tooling: 30 * 86400
        case .goal: 30 * 86400
        case .style: 14 * 86400
        case .channel: 7 * 86400
        }
    }

    /// Per-class Active budgets (excess Active → demoted to Provisional).
    public var activeBudget: Int {
        switch self {
        case .style: 4
        case .identity: 4
        case .tooling: 5
        case .veto: 3
        case .goal: 3
        case .channel: 1
        }
    }

    public static let overflowPool = 5
}

public enum CueFamily: String, Sendable, CaseIterable, Codable {
    case explicit, structural, behavioral, recurrence

    public var weight: Double {
        switch self {
        case .explicit: 1.0
        case .structural: 0.9
        case .behavioral: 0.7
        case .recurrence: 0.6
        }
    }
}

public enum FacetUserState: String, Sendable, Codable {
    case auto, pinned, forgotten
}

public enum FacetState: String, Sendable, Codable {
    case active, provisional, candidate
}

public struct FacetEvidence: Sendable {
    public var `class`: FacetClass
    public var key: String // "style/verbosity"
    public var value: String // "terse"
    public var cue: CueFamily
    public var evidenceRef: String // set-dedup key: "episode:<id>", "nudge:<id>"
    public var observedAt: Date

    public init(class klass: FacetClass, key: String, value: String, cue: CueFamily,
                evidenceRef: String, observedAt: Date) {
        self.class = klass
        self.key = key
        self.value = value
        self.cue = cue
        self.evidenceRef = evidenceRef
        self.observedAt = observedAt
    }
}

public struct FacetResult: Sendable, Equatable {
    public var key: String
    public var `class`: FacetClass
    public var value: String
    public var state: FacetState
    public var stability: Double
    public var evidenceCount: Int
    public var firstSeenAt: Date
    public var lastSeenAt: Date
}

public enum FacetEngine {
    public static let tauPromote = 1.5
    public static let tauProvisional = 0.7
    public static let tauEvict = 0.4

    /// Pure rebuild: full evidence stream + user overrides → scored facets.
    /// Evicted facets (< tauEvict) are absent from the result (caller deletes).
    public static func rebuild(evidence: [FacetEvidence],
                               userStates: [String: FacetUserState] = [:],
                               now: Date = .now) -> [FacetResult] {
        // Set-dedup by (key, value, evidenceRef), then group per key.
        var seenRefs = Set<String>()
        var byKey: [String: [FacetEvidence]] = [:]
        for item in evidence {
            let ref = "\(item.key)|\(item.value)|\(item.evidenceRef)"
            guard !seenRefs.contains(ref) else { continue }
            seenRefs.insert(ref)
            byKey[item.key, default: []].append(item)
        }

        var results: [FacetResult] = []
        for (key, items) in byKey {
            guard let klass = items.first?.class else { continue }
            if userStates[key] == .forgotten { continue } // stability 0 → evicted

            // Value conflict: winner = argmax of summed weighted-recency.
            var scoreByValue: [String: Double] = [:]
            for item in items {
                let age = max(0, now.timeIntervalSince(item.observedAt))
                scoreByValue[item.value, default: 0] += item.cue.weight * exp(-age / klass.halfLife)
            }
            guard let winner = scoreByValue.max(by: { $0.value < $1.value })?.key else { continue }
            let winning = items.filter { $0.value == winner }

            // base = Σ over cue families present: weight × decay(newest) × ln(1+count)
            var base = 0.0
            let byFamily = Dictionary(grouping: winning, by: \.cue)
            for (family, familyItems) in byFamily {
                let newest = familyItems.map(\.observedAt).max() ?? now
                let age = max(0, now.timeIntervalSince(newest))
                base += family.weight * exp(-age / klass.halfLife) * log(1 + Double(familyItems.count))
            }
            let explicitMult = byFamily[.explicit] != nil ? 2.0 : 1.0
            var stability = base * explicitMult
            if userStates[key] == .pinned { stability = .greatestFiniteMagnitude }

            guard stability >= tauEvict else { continue }
            let state: FacetState = stability >= tauPromote ? .active
                : stability >= tauProvisional ? .provisional : .candidate

            results.append(FacetResult(
                key: key, class: klass, value: winner, state: state, stability: stability,
                evidenceCount: winning.count,
                firstSeenAt: winning.map(\.observedAt).min() ?? now,
                lastSeenAt: winning.map(\.observedAt).max() ?? now
            ))
        }

        return enforceBudgets(results)
    }

    /// Per-class Active budgets + a shared overflow pool; excess Active facets
    /// (lowest stability first) demote to Provisional.
    static func enforceBudgets(_ facets: [FacetResult]) -> [FacetResult] {
        var out = facets
        var overflowLeft = FacetClass.overflowPool
        for klass in FacetClass.allCases {
            let activeIdx = out.indices
                .filter { out[$0].class == klass && out[$0].state == .active }
                .sorted { out[$0].stability > out[$1].stability }
            if activeIdx.count > klass.activeBudget {
                for (position, idx) in activeIdx.enumerated() where position >= klass.activeBudget {
                    if overflowLeft > 0 {
                        overflowLeft -= 1
                    } else {
                        out[idx].state = .provisional
                    }
                }
            }
        }
        return out
    }

    /// Render the Active facets as prompt lines, most stable first, capped.
    public static func promptSection(_ facets: [FacetResult], cap: Int = 25) -> String? {
        let active = facets.filter { $0.state == .active }
            .sorted { $0.stability > $1.stability }
            .prefix(cap)
        guard !active.isEmpty else { return nil }
        let lines = active.map { "- \($0.key): \($0.value)" }
        return "What you know about how the user likes things:\n" + lines.joined(separator: "\n")
    }
}

/// Evidence producers that are pure text analysis (wiring lives in the app).
public enum FacetCues {
    /// Explicit preference statements in extracted facts: "Me prefers terse
    /// answers", "Me always/never …". Key = style/<first-content-word-pair>.
    public static func explicitCandidates(fromFacts facts: [(id: String, text: String)],
                                          now: Date = .now) -> [FacetEvidence] {
        var out: [FacetEvidence] = []
        for fact in facts {
            let lower = fact.text.lowercased()
            guard lower.contains("prefer") || lower.contains("always ")
                || lower.contains("never ") || lower.contains("likes to be")
                || lower.contains("wants jarvis") || lower.contains("hates when") else { continue }
            let isVeto = lower.contains("never ") || lower.contains("hates when")
            out.append(FacetEvidence(
                class: isVeto ? .veto : .style,
                key: (isVeto ? "veto/" : "style/") + slug(fact.text),
                value: String(fact.text.prefix(120)),
                cue: .explicit,
                evidenceRef: "fact:\(fact.id)",
                observedAt: now
            ))
        }
        return out
    }

    static func slug(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 && !["user", "prefers", "always", "never", "wants", "hates", "when", "jarvis"].contains($0) }
            .prefix(2)
            .joined(separator: "-")
    }
}
