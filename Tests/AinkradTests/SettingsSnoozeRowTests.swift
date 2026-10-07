import AinkradAppKitContract
import Foundation
import Testing

@testable import Ainkrad

/// Notifications → When → Snooze reads the snooze deadline twice (help line and
/// first option). Pinned before that read loses its force unwrap.
@Suite("Settings snooze row")
@MainActor
struct SettingsSnoozeRowTests {
    private let path = SettingsPath(["workspace", "notifications", "when", "snooze"])

    private func row(snoozedUntil: Date?) throws -> (help: String?, options: [String], selection: String) {
        let environment = AppEnvironment.preview()
        let center = try #require(environment.signalCenter)
        center.rules.suppression.snoozedUntil = snoozedUntil
        let field = try #require(HostSettingsCatalog.build(environment: environment).field(at: path))
        guard case .select(let options, let selection) = field.kind else {
            Issue.record("snooze is not a select row")
            return (nil, [], "")
        }
        return (field.help, options.map(\.title), selection.wrappedValue)
    }

    @Test("a live snooze names the time it ends, in the help and the first option")
    func liveSnooze() throws {
        let until = Date().addingTimeInterval(3600)
        let time = DateFormatter()
        time.dateFormat = "HH:mm"
        let row = try row(snoozedUntil: until)
        #expect(row.help == "Quiet until \(time.string(from: until)).")
        #expect(row.options.prefix(2) == ["Quiet until \(time.string(from: until))", "Resume now"])
        #expect(row.selection == "snoozed")
    }

    @Test("a lapsed or absent snooze reads as not snoozed")
    func noSnooze() throws {
        for until in [nil, Date().addingTimeInterval(-60)] {
            let row = try row(snoozedUntil: until)
            #expect(row.help == "Pause interruptions for a while.")
            #expect(row.options.first == "Not snoozed")
            #expect(row.selection == "off")
        }
    }
}
