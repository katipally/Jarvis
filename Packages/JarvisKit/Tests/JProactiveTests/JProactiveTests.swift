import Foundation
import Testing
@testable import JProactive

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
    cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

@Test func cronParsesAndRejects() {
    #expect(CronSchedule("0 9 * * *") != nil)
    #expect(CronSchedule("*/15 * * * *") != nil)
    #expect(CronSchedule("0 9 * * 1-5") != nil)
    #expect(CronSchedule("bad") == nil)
    #expect(CronSchedule("60 9 * * *") == nil) // minute out of range
    #expect(CronSchedule("0 9 * *") == nil)    // too few fields
}

@Test func cronDailyNineAM() {
    let schedule = CronSchedule("0 9 * * *")!
    let from = date(2026, 7, 19, 8, 30)
    let next = schedule.nextFire(after: from, calendar: cal)
    #expect(next == date(2026, 7, 19, 9, 0))
}

@Test func cronRollsToNextDay() {
    let schedule = CronSchedule("0 9 * * *")!
    let from = date(2026, 7, 19, 9, 30) // already past 9am
    let next = schedule.nextFire(after: from, calendar: cal)
    #expect(next == date(2026, 7, 20, 9, 0))
}

@Test func cronEveryFifteenMinutes() {
    let schedule = CronSchedule("*/15 * * * *")!
    let from = date(2026, 7, 19, 10, 7)
    let next = schedule.nextFire(after: from, calendar: cal)
    #expect(next == date(2026, 7, 19, 10, 15))
}

@Test func cronWeekdaysOnly() {
    let schedule = CronSchedule("0 9 * * 1-5")! // Mon-Fri
    // 2026-07-19 is a Sunday → next weekday 9am is Monday the 20th.
    let from = date(2026, 7, 19, 12, 0)
    let next = schedule.nextFire(after: from, calendar: cal)
    #expect(next == date(2026, 7, 20, 9, 0))
}
