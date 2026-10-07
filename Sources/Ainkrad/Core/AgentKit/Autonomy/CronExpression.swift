import Foundation

/// A minimal cron: minute/hour/day-of-week sets (nil = wildcard). Sufficient for
/// the NL schedules this slice compiles ("every weekday 9am", "hourly", "daily 8am").
struct CronExpression: Codable, Equatable, Sendable {
    let minutes: Set<Int>?
    let hours: Set<Int>?
    let daysOfWeek: Set<Int>?  // Calendar weekday: 1=Sun … 7=Sat

    init(minutes: Set<Int>? = nil, hours: Set<Int>? = nil, daysOfWeek: Set<Int>? = nil) {
        self.minutes = minutes
        self.hours = hours
        self.daysOfWeek = daysOfWeek
    }

    var text: String {
        func f(_ s: Set<Int>?) -> String { s.map { $0.sorted().map(String.init).joined(separator: ",") } ?? "*" }
        return "\(f(minutes)) \(f(hours)) * * \(f(daysOfWeek))"
    }

    func nextFireDate(after date: Date, calendar: Calendar = .current) -> Date? {
        if minutes?.isEmpty == true || hours?.isEmpty == true || daysOfWeek?.isEmpty == true { return nil }
        // Start at the top of the next minute.
        guard
            var candidate = calendar.date(
                byAdding: .minute, value: 1,
                to: calendar.date(bySetting: .second, value: 0, of: date) ?? date)
        else { return nil }
        candidate = calendar.date(bySetting: .second, value: 0, of: candidate) ?? candidate
        let horizon = calendar.date(byAdding: .day, value: 366, to: date) ?? date
        while candidate <= horizon {
            let c = calendar.dateComponents([.minute, .hour, .weekday], from: candidate)
            let minuteOK = minutes?.contains(c.minute ?? -1) ?? true
            let hourOK = hours?.contains(c.hour ?? -1) ?? true
            let dowOK = daysOfWeek?.contains(c.weekday ?? -1) ?? true
            if minuteOK && hourOK && dowOK { return candidate }
            candidate = calendar.date(byAdding: .minute, value: 1, to: candidate) ?? horizon.addingTimeInterval(1)
        }
        return nil
    }
}
