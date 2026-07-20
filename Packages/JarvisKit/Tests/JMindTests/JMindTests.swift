import Foundation
import Testing
@testable import JMind

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

@Suite struct AdmissionTests {
    @Test func dedupeWindowDropsRepeats() {
        var window = DedupeWindow(ttl: 300)
        let first = window.admit("a", now: t0)
        let repeated = window.admit("a", now: t0.addingTimeInterval(299))
        let expired = window.admit("a", now: t0.addingTimeInterval(301))
        let other = window.admit("b", now: t0.addingTimeInterval(301))
        #expect(first && !repeated && expired && other)
    }

    @Test func rateLimiterRefills() {
        var limiter = RateLimiter(capacity: 2, refillPerSecond: 1)
        let a = limiter.admit(family: "mail", now: t0)
        let b = limiter.admit(family: "mail", now: t0)
        let empty = limiter.admit(family: "mail", now: t0)
        let otherFamily = limiter.admit(family: "calendar", now: t0)
        let refilled = limiter.admit(family: "mail", now: t0.addingTimeInterval(1.5))
        #expect(a && b && !empty && otherFamily && refilled)
    }

    @Test func duplicateDoesNotConsumeRateToken() {
        var admission = TriggerAdmission(dedupeTTL: 300, capacity: 1, refillPerSecond: 0)
        let trigger = Trigger(source: "mail", dedupeKey: "x", gateSummary: "s")
        let first = admission.admit(trigger, now: t0)
        let dup = admission.admit(trigger, now: t0) // deduped BEFORE rate
        let other = admission.admit(Trigger(source: "mail", dedupeKey: "y", gateSummary: "s"), now: t0)
        #expect(first == .admitted)
        #expect(dup == .duplicate)
        #expect(other == .rateLimited) // token spent by x only
    }

    @Test func promotionBudgetSlidesAndDowngrades() {
        var budget = PromotionBudget(maxPerHour: 2)
        let a = budget.tryConsume(now: t0)
        let b = budget.tryConsume(now: t0)
        let full = budget.tryConsume(now: t0.addingTimeInterval(1800))
        let slid = budget.tryConsume(now: t0.addingTimeInterval(3601))
        var disabled = PromotionBudget(maxPerHour: 0)
        let off = disabled.tryConsume(now: t0)
        #expect(a && b && !full && slid && !off)
    }
}

@Suite struct TriageTests {
    @Test func tolerantParsing() {
        #expect(TriageAction.parse("drop") == .drop)
        #expect(TriageAction.parse("  ESCALATE ") == .escalate)
        #expect(TriageAction.parse("I think we should react to this") == .react)
        #expect(TriageAction.parse("total garbage") == .drop) // bias to drop
        #expect(TriageAction.parse("") == .drop)
    }

    @Test func gateMapping() {
        #expect(GateDecision.from(.drop) == .drop(acknowledge: false))
        #expect(GateDecision.from(.acknowledge) == .drop(acknowledge: true))
        #expect(GateDecision.from(.react) == .promote(escalated: false))
        #expect(GateDecision.from(.escalate) == .promote(escalated: true))
    }
}

@Suite struct DeliveryPlannerTests {
    @Test func meetingStages() {
        let meeting = DeliveryPlanner.Event(category: "meeting", overlapKey: "standup@10",
                                            title: "Standup", at: t0)
        // 30 min out → heads_up
        #expect(DeliveryPlanner.plan(events: [meeting], now: t0.addingTimeInterval(-1800)).first?.stage == "heads_up")
        // 5 min out → final_call
        #expect(DeliveryPlanner.plan(events: [meeting], now: t0.addingTimeInterval(-300)).first?.stage == "final_call")
        // 5 min ago → starting_now
        #expect(DeliveryPlanner.plan(events: [meeting], now: t0.addingTimeInterval(300)).first?.stage == "starting_now")
        // 2 hours out (beyond lookahead) → nothing
        #expect(DeliveryPlanner.plan(events: [meeting], now: t0.addingTimeInterval(-7200)).isEmpty)
        // 30 min past → nothing
        #expect(DeliveryPlanner.plan(events: [meeting], now: t0.addingTimeInterval(1800)).isEmpty)
    }

    @Test func commitmentStages() {
        let commitment = DeliveryPlanner.Event(category: "commitment", overlapKey: "c1",
                                               title: "send the report", at: t0)
        #expect(DeliveryPlanner.plan(events: [commitment], now: t0.addingTimeInterval(-600)).first?.stage == "soon")
        #expect(DeliveryPlanner.plan(events: [commitment], now: t0.addingTimeInterval(600)).first?.stage == "due")
    }

    @Test func stableKeyIsDeterministicPerStage() {
        let a = DeliveryPlanner.stableKey(category: "meeting", overlapKey: "x", stage: "heads_up")
        #expect(a == DeliveryPlanner.stableKey(category: "meeting", overlapKey: "x", stage: "heads_up"))
        #expect(a != DeliveryPlanner.stableKey(category: "meeting", overlapKey: "x", stage: "final_call"))
    }
}

@Suite struct FacetEngineTests {
    private func evidence(_ key: String, _ value: String, cue: CueFamily,
                          klass: FacetClass = .style, ref: String, age: TimeInterval) -> FacetEvidence {
        FacetEvidence(class: klass, key: key, value: value, cue: cue,
                      evidenceRef: ref, observedAt: t0.addingTimeInterval(-age))
    }

    @Test func explicitEvidencePromotes() {
        // One fresh explicit statement: base = 1.0 × ~1 × ln(2) ≈ 0.693 → ×2 = 1.386 (provisional)
        let single = FacetEngine.rebuild(
            evidence: [evidence("style/verbosity", "terse", cue: .explicit, ref: "e1", age: 60)],
            now: t0)
        #expect(single.first?.state == .provisional)
        #expect(abs((single.first?.stability ?? 0) - 2 * log(2)) < 0.01)

        // Two explicit statements: 1.0 × ln(3) × 2 ≈ 2.197 → active
        let double = FacetEngine.rebuild(
            evidence: [
                evidence("style/verbosity", "terse", cue: .explicit, ref: "e1", age: 60),
                evidence("style/verbosity", "terse", cue: .explicit, ref: "e2", age: 30),
            ], now: t0)
        #expect(double.first?.state == .active)
    }

    @Test func decayEvictsStaleFacets() {
        // Style half-life 14d. A behavioral-only facet aged 5 half-lives:
        // 0.7 × exp(-5) × ln(2) ≈ 0.0033 < 0.4 → evicted (absent).
        let stale = FacetEngine.rebuild(
            evidence: [evidence("style/emoji", "none", cue: .behavioral, ref: "b1", age: 70 * 86400)],
            now: t0)
        #expect(stale.isEmpty)
    }

    @Test func evidenceRefSetDedup() {
        // The same ref reported twice counts once.
        let facets = FacetEngine.rebuild(
            evidence: [
                evidence("style/verbosity", "terse", cue: .explicit, ref: "e1", age: 60),
                evidence("style/verbosity", "terse", cue: .explicit, ref: "e1", age: 60),
            ], now: t0)
        #expect(facets.first?.evidenceCount == 1)
    }

    @Test func valueConflictArgmax() {
        // Fresh "terse" × 2 beats stale "verbose" × 1.
        let facets = FacetEngine.rebuild(
            evidence: [
                evidence("style/verbosity", "verbose", cue: .explicit, ref: "old", age: 40 * 86400),
                evidence("style/verbosity", "terse", cue: .explicit, ref: "n1", age: 60),
                evidence("style/verbosity", "terse", cue: .explicit, ref: "n2", age: 30),
            ], now: t0)
        #expect(facets.count == 1)
        #expect(facets.first?.value == "terse")
    }

    @Test func pinnedSurvivesForgottenDies() {
        let stale = [evidence("style/emoji", "none", cue: .behavioral, ref: "b1", age: 200 * 86400)]
        let pinned = FacetEngine.rebuild(evidence: stale, userStates: ["style/emoji": .pinned], now: t0)
        #expect(pinned.first?.state == .active)

        let fresh = [evidence("style/verbosity", "terse", cue: .explicit, ref: "e1", age: 60)]
        let forgotten = FacetEngine.rebuild(evidence: fresh, userStates: ["style/verbosity": .forgotten], now: t0)
        #expect(forgotten.isEmpty)
    }

    @Test func activeBudgetDemotes() {
        // channel budget = 1, overflow pool 5 → flood 8 active channel facets;
        // 1 in budget + 5 overflow stay active, the remaining 2 demote.
        var items: [FacetEvidence] = []
        for i in 0..<8 {
            for j in 0..<3 {
                items.append(evidence("channel/c\(i)", "v", cue: .explicit, klass: .channel,
                                      ref: "r\(i)-\(j)", age: 60))
            }
        }
        let facets = FacetEngine.rebuild(evidence: items, now: t0)
        let active = facets.filter { $0.state == .active }.count
        #expect(active == 1 + FacetClass.overflowPool)
    }

    @Test func promptSectionRendersActiveOnly() {
        let facets = FacetEngine.rebuild(
            evidence: [
                evidence("style/verbosity", "terse", cue: .explicit, ref: "e1", age: 60),
                evidence("style/verbosity", "terse", cue: .explicit, ref: "e2", age: 30),
            ], now: t0)
        let section = FacetEngine.promptSection(facets)
        #expect(section?.contains("style/verbosity: terse") == true)
        #expect(FacetEngine.promptSection([]) == nil)
    }

    @Test func explicitCueDetection() {
        let candidates = FacetCues.explicitCandidates(
            fromFacts: [
                (id: "f1", text: "Me prefers terse answers without preamble"),
                (id: "f2", text: "Me lives in Denver"),
                (id: "f3", text: "Me never wants notifications during meetings"),
            ], now: t0)
        #expect(candidates.count == 2)
        #expect(candidates.contains { $0.class == .veto })
        #expect(candidates.contains { $0.class == .style })
    }
}
