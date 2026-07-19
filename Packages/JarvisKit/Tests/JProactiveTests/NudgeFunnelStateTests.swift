import Foundation
import Testing
@testable import JProactive

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func day(_ y: Int, _ mo: Int, _ d: Int) -> Date {
    cal.date(from: DateComponents(year: y, month: mo, day: d, hour: 12))!
}

@Test func dismissalQuadruplesMultiplier() {
    let start = NudgeFunnelState(day: day(2026, 7, 19), multiplier: 1)
    let bumped = start.bumped(now: day(2026, 7, 19), calendar: cal)
    #expect(bumped.multiplier == 4)
}

@Test func dismissalMultiplierCaps() {
    var state = NudgeFunnelState(day: day(2026, 7, 19), multiplier: 8)
    state = state.bumped(now: day(2026, 7, 19), calendar: cal) // 32 → capped at 16
    #expect(state.multiplier == NudgeFunnelState.cap)
}

@Test func multiplierDecaysHalvingPerDay() {
    let state = NudgeFunnelState(day: day(2026, 7, 19), multiplier: 16)
    // Two days later → 16 / 2^2 = 4.
    let decayed = state.decayed(now: day(2026, 7, 21), calendar: cal)
    #expect(decayed.multiplier == 4)
    #expect(decayed.day == cal.startOfDay(for: day(2026, 7, 21)))
}

@Test func decayNeverBelowOne() {
    let state = NudgeFunnelState(day: day(2026, 7, 19), multiplier: 2)
    let decayed = state.decayed(now: day(2026, 8, 30), calendar: cal) // many days
    #expect(decayed.multiplier == 1)
}

@Test func decayIsNoopWithinSameDay() {
    let state = NudgeFunnelState(day: day(2026, 7, 19), multiplier: 8)
    let same = state.decayed(now: day(2026, 7, 19), calendar: cal)
    #expect(same == state)
}
