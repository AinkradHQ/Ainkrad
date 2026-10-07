import Foundation

enum NaturalLanguageCronCompiler {
    private static let weekdayNames: [String: Int] = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
        "thursday": 5, "friday": 6, "saturday": 7,
    ]

    static func compile(_ text: String) -> CronExpression? {
        let s = text.lowercased()

        // Day-of-week set.
        var dow: Set<Int>?
        if s.contains("weekday") {
            dow = [2, 3, 4, 5, 6]
        } else {
            let named = weekdayNames.filter { s.contains($0.key) }.map(\.value)
            if !named.isEmpty { dow = Set(named) }
        }

        // Time clause.
        let time = parseTime(s)

        if s.contains("hourly") || s.contains("every hour") {
            return CronExpression(minutes: [time?.minute ?? 0], hours: nil, daysOfWeek: dow)
        }
        if let time {
            return CronExpression(minutes: [time.minute], hours: [time.hour], daysOfWeek: dow)
        }
        if s.contains("daily") || s.contains("every day") {
            return CronExpression(minutes: [0], hours: [9], daysOfWeek: dow)  // default 9am
        }
        if dow != nil {
            return CronExpression(minutes: [0], hours: [9], daysOfWeek: dow)
        }
        return nil
    }

    /// Parses "9am", "9:30am", "5pm", "17:00", "at 8" → (hour, minute) in 24h.
    private static func parseTime(_ s: String) -> (hour: Int, minute: Int)? {
        let pattern = #"(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        guard let re = try? NSRegularExpression(pattern: pattern),
            let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))
        else { return nil }
        func group(_ i: Int) -> String? {
            guard m.range(at: i).location != NSNotFound, let r = Range(m.range(at: i), in: s) else { return nil }
            return String(s[r])
        }
        guard let hourStr = group(1), var hour = Int(hourStr), (0...23).contains(hour) else { return nil }
        let minute = group(2).flatMap(Int.init) ?? 0
        let meridiem = group(3)
        if meridiem == "pm", hour < 12 { hour += 12 }
        if meridiem == "am", hour == 12 { hour = 0 }
        // Require a real time signal so "audit 3 modules" doesn't parse as 3am.
        guard meridiem != nil || s.contains(":") || s.contains("at ") else { return nil }
        return (hour, minute)
    }
}
