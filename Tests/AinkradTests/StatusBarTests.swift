import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

/// Pure formatters + models behind the full-screen status bar (AIN-109):
/// `NetworkStatus`, `BatteryInfo`, `StatusClock`, and the
/// `GlobalSettings.showFullScreenStatusBar` toggle. No AppKit/system
/// providers here — `SystemStatusMonitor` and the full-screen detection are
/// build-verified only, per the issue.
@Suite("Full-screen status bar")
struct StatusBarTests {

    // MARK: - NetworkStatus

    @Test("label + symbolName for each network status")
    func networkStatusLabelsAndSymbols() {
        #expect(NetworkStatus.wifi.label == "Wi-Fi")
        #expect(NetworkStatus.wifi.symbolName == "wifi")

        #expect(NetworkStatus.ethernet.label == "Ethernet")
        #expect(NetworkStatus.ethernet.symbolName == "cable.connector")

        #expect(NetworkStatus.offline.label == "Offline")
        #expect(NetworkStatus.offline.symbolName == "wifi.slash")

        #expect(NetworkStatus.other.label == "Connected")
        #expect(NetworkStatus.other.symbolName == "network")
    }

    // MARK: - BatteryInfo

    @Test("displayText formats the percent")
    func batteryDisplayText() {
        #expect(BatteryInfo(percent: 0, isCharging: false).displayText == "0%")
        #expect(BatteryInfo(percent: 83, isCharging: false).displayText == "83%")
        #expect(BatteryInfo(percent: 100, isCharging: true).displayText == "100%")
    }

    @Test("symbolName maps percent to the nearest battery glyph when not charging")
    func batterySymbolNameNotCharging() {
        #expect(BatteryInfo(percent: 0, isCharging: false).symbolName == "battery.0")
        #expect(BatteryInfo(percent: 25, isCharging: false).symbolName == "battery.25")
        #expect(BatteryInfo(percent: 50, isCharging: false).symbolName == "battery.50")
        #expect(BatteryInfo(percent: 83, isCharging: false).symbolName == "battery.75")
        #expect(BatteryInfo(percent: 100, isCharging: false).symbolName == "battery.100")
    }

    @Test("symbolName at the exact case boundaries rounds up to the next glyph")
    func batterySymbolNameBoundaries() {
        #expect(BatteryInfo(percent: 13, isCharging: false).symbolName == "battery.25")
        #expect(BatteryInfo(percent: 38, isCharging: false).symbolName == "battery.50")
        #expect(BatteryInfo(percent: 63, isCharging: false).symbolName == "battery.75")
        #expect(BatteryInfo(percent: 88, isCharging: false).symbolName == "battery.100")
    }

    @Test("symbolName always shows the bolt glyph while charging, regardless of percent")
    func batterySymbolNameCharging() {
        #expect(BatteryInfo(percent: 12, isCharging: true).symbolName == "battery.100.bolt")
        #expect(BatteryInfo(percent: 100, isCharging: true).symbolName == "battery.100.bolt")
    }

    // MARK: - StatusClock

    @Test("string(from:) formats a fixed date deterministically for a fixed calendar/locale")
    func statusClockFormatsDeterministically() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let locale = Locale(identifier: "en_US_POSIX")
        // 2023-11-14 22:13:20 UTC (Tuesday).
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let result = StatusClock.string(from: date, calendar: calendar, locale: locale)

        // ICU's "j:mm" template renders a narrow no-break space (U+202F)
        // before the AM/PM designator, not a regular space — match that
        // exactly rather than a plain " PM" literal.
        #expect(result.time == "10:13\u{202F}PM")
        #expect(result.date == "Tue, Nov 14")
    }

    // MARK: - GlobalSettings.showFullScreenStatusBar

    @Test("defaults to true with no prior write")
    func showFullScreenStatusBarDefaultsToTrue() {
        #expect(GlobalSettings().showFullScreenStatusBar == true)
    }

    @Test("a legacy payload without the key decodes to the default (true)")
    func legacyPayloadWithoutKeyDecodesToDefault() throws {
        let legacy = Data(#"{"theme":"cyberPurple"}"#.utf8)
        let decoded = try JSONDecoder().decode(GlobalSettings.self, from: legacy)
        #expect(decoded.showFullScreenStatusBar == true)
    }

    @Test("a written false value round-trips through the persistence store")
    func showFullScreenStatusBarRoundTrips() {
        let store = InMemoryPersistenceStore()
        var settings = GlobalSettings()
        settings.showFullScreenStatusBar = false
        store.save(settings)
        #expect(store.load(GlobalSettings.self)?.showFullScreenStatusBar == false)
    }
}
