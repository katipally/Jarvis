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
