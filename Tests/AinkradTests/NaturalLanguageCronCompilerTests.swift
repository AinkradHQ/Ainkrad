import Foundation
import Testing

@testable import Ainkrad

@Suite("NaturalLanguageCronCompiler")
struct NaturalLanguageCronCompilerTests {
    @Test func everyWeekday9am() {
        let cron = NaturalLanguageCronCompiler.compile("every weekday at 9am")
        #expect(cron?.hours == [9])
        #expect(cron?.minutes == [0])
        #expect(cron?.daysOfWeek == [2, 3, 4, 5, 6])
    }

    @Test func dailyWithMinutes() {
        let cron = NaturalLanguageCronCompiler.compile("every day at 8:30am")
        #expect(cron?.hours == [8])
        #expect(cron?.minutes == [30])
        #expect(cron?.daysOfWeek == nil)
    }

    @Test func pmConvertsTo24h() {
        let cron = NaturalLanguageCronCompiler.compile("daily at 5pm")
        #expect(cron?.hours == [17])
    }

    @Test func hourly() {
        let cron = NaturalLanguageCronCompiler.compile("hourly")
        #expect(cron?.minutes == [0])
        #expect(cron?.hours == nil)
    }

    @Test func namedWeekday() {
        let cron = NaturalLanguageCronCompiler.compile("every monday at 07:00")
        #expect(cron?.daysOfWeek == [2])
        #expect(cron?.hours == [7])
    }

    @Test func unparseableReturnsNil() {
        #expect(NaturalLanguageCronCompiler.compile("whenever I feel like it") == nil)
    }
}
