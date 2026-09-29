import Testing
import Foundation
import AinkradSignal
@testable import Ainkrad

@MainActor
@Suite("Notification health readout")
struct NotificationStatsTests {
    @Test("percentages are whole numbers")
    func percentIsCoarse() {
        // A read rate quoted to a decimal place claims a precision that a few
        // dozen events cannot support.
        #expect(NotificationStats.percent(0.0) == "0%")
        #expect(NotificationStats.percent(1.0) == "100%")
        #expect(NotificationStats.percent(1.0 / 3.0) == "33%")
        #expect(NotificationStats.percent(0.666) == "67%")
    }

    @Test("durations are coarse, and an absent one is a dash not a zero")
    func durationFormatting() {
        // "nothing has been read" and "read instantly" are different facts,
        // and 0s would state the second when the first is true.
        #expect(NotificationStats.duration(nil) == "—")
        #expect(NotificationStats.duration(0) == "0s")
        #expect(NotificationStats.duration(45) == "45s")
        #expect(NotificationStats.duration(90) == "2m")
        #expect(NotificationStats.duration(3600) == "1h")
        #expect(NotificationStats.duration(90_000) == "1d")
    }

    @Test("each window is the span it names")
    func windowSpans() {
        #expect(NotificationStats.Window.day.seconds == 86_400)
        #expect(NotificationStats.Window.week.seconds == 7 * 86_400)
        #expect(NotificationStats.Window.month.seconds == 30 * 86_400)
        #expect(NotificationStats.Window.allCases.map(\.label)
                == ["24 hours", "7 days", "30 days"])
    }
}
