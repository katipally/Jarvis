import Foundation

/// A parsed 5-field cron expression: `minute hour day-of-month month day-of-week`.
/// Supports `*`, `*/n`, `a-b`, and comma lists. Day-of-week 0/7 = Sunday.
public struct CronSchedule: Sendable {
    let minutes: Set<Int>
    let hours: Set<Int>
    let daysOfMonth: Set<Int>
    let months: Set<Int>
    let daysOfWeek: Set<Int>

    public init?(_ expression: String) {
        let fields = expression.split(separator: " ").map(String.init)
        guard fields.count == 5,
              let minutes = Self.parse(fields[0], min: 0, max: 59),
              let hours = Self.parse(fields[1], min: 0, max: 23),
              let daysOfMonth = Self.parse(fields[2], min: 1, max: 31),
              let months = Self.parse(fields[3], min: 1, max: 12),
              var daysOfWeek = Self.parse(fields[4], min: 0, max: 7) else {
            return nil
        }
        if daysOfWeek.contains(7) { daysOfWeek.insert(0) } // normalize Sunday
        self.minutes = minutes
        self.hours = hours
        self.daysOfMonth = daysOfMonth
        self.months = months
        self.daysOfWeek = daysOfWeek
    }

    private static func parse(_ field: String, min: Int, max: Int) -> Set<Int>? {
        var result: Set<Int> = []
        for part in field.split(separator: ",") {
            var step = 1
            var base = String(part)
            if let slash = base.firstIndex(of: "/") {
                guard let s = Int(base[base.index(after: slash)...]) else { return nil }
                step = s
                base = String(base[..<slash])
            }
            let lower: Int, upper: Int
            if base == "*" {
                lower = min; upper = max
            } else if let dash = base.firstIndex(of: "-") {
                guard let a = Int(base[..<dash]), let b = Int(base[base.index(after: dash)...]) else { return nil }
                lower = a; upper = b
            } else if let n = Int(base) {
                lower = n; upper = n
            } else {
                return nil
            }
            guard lower >= min, upper <= max, lower <= upper, step > 0 else { return nil }
            result.formUnion(stride(from: lower, through: upper, by: step))
        }
        return result.isEmpty ? nil : result
    }

    /// First matching minute strictly after `date`. Searches up to ~13 months.
    public func nextFire(after date: Date, calendar: Calendar = .current) -> Date? {
        guard var candidate = calendar.date(bySetting: .second, value: 0, of: date) else { return nil }
        candidate = candidate.addingTimeInterval(60)
        let horizon = candidate.addingTimeInterval(400 * 86400)
        while candidate <= horizon {
            let c = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: candidate)
            let weekday = (c.weekday ?? 1) - 1 // Calendar 1-7 (Sun-Sat) → cron 0-6
            if let minute = c.minute, let hour = c.hour, let day = c.day, let month = c.month,
               minutes.contains(minute), hours.contains(hour), months.contains(month),
               daysOfMonth.contains(day), daysOfWeek.contains(weekday) {
                return candidate
            }
            candidate = candidate.addingTimeInterval(60)
        }
        return nil
    }
}
