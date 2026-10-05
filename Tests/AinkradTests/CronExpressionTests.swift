import Foundation
import Testing

@testable import Ainkrad

@Suite("CronExpression")
struct CronExpressionTests {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")!
        return f.date(from: s)!
    }

    @Test func dailyAt9amNext() {
        let cron = CronExpression(minutes: [0], hours: [9], daysOfWeek: nil)
        let next = cron.nextFireDate(after: date("2026-07-18T08:30:00Z"), calendar: utc)
        #expect(next == date("2026-07-18T09:00:00Z"))
    }

    @Test func rollsToNextDayWhenPast() {
        let cron = CronExpression(minutes: [0], hours: [9], daysOfWeek: nil)
        let next = cron.nextFireDate(after: date("2026-07-18T10:00:00Z"), calendar: utc)
        #expect(next == date("2026-07-19T09:00:00Z"))
    }

    @Test func weekdayOnlySkipsWeekend() {
        // 2026-07-18 is a Saturday; weekdays = Mon(2)…Fri(6).
        let cron = CronExpression(minutes: [0], hours: [9], daysOfWeek: [2, 3, 4, 5, 6])
        let next = cron.nextFireDate(after: date("2026-07-18T09:30:00Z"), calendar: utc)
        #expect(next == date("2026-07-20T09:00:00Z"))  // Monday
    }

    @Test func hourlyMatchesTopOfNextHour() {
        let cron = CronExpression(minutes: [0], hours: nil, daysOfWeek: nil)
        let next = cron.nextFireDate(after: date("2026-07-18T08:15:00Z"), calendar: utc)
        #expect(next == date("2026-07-18T09:00:00Z"))
    }
}
