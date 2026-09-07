import Testing
import Foundation
import AinkradSignal
@testable import Ainkrad

@MainActor
@Suite("Signal bootstrap")
final class SignalBootstrapTests {
    @Test("the store lands beside the cache in Application Support, not in the user's vault")
    func storeLocation() {
        let root = URL(fileURLWithPath: "/tmp/appsupport/com.ainkrad.app", isDirectory: true)
        let url = AppEnvironment.signalStoreURL(applicationSupport: root)
        #expect(url.lastPathComponent == "signal.sqlite")
        #expect(url.path.hasPrefix("/tmp/appsupport"))
        #expect(!url.path.contains("/Cache/"),
                "the feed is the record, not a derived cache - a purge must not erase history")
        #expect(!url.path.contains("WorkShop"), "the feed is machine state, not vault data")
    }

    @Test("an unopenable store yields a degraded center rather than a crash")
    func degradesRatherThanCrashes() {
        // A path under a file (not a directory) cannot be opened as a database.
        let blocked = URL(fileURLWithPath: "/dev/null/impossible/signal.sqlite")
        let center = AppEnvironment.makeSignalCenter(storeURL: blocked,
                                                     preferences: SignalPreferences())
        #expect(center.isDegraded)
        center.emit(SignalDraft(kind: "test.event", severity: .info, title: "still works"),
                    from: .host)
        #expect(center.recent.count >= 1, "the in-memory ring buffer still serves the feed")
    }

    @Test("a degraded center says so in the feed itself")
    func degradedAnnouncesItself() {
        let blocked = URL(fileURLWithPath: "/dev/null/impossible/signal.sqlite")
        let center = AppEnvironment.makeSignalCenter(storeURL: blocked,
                                                     preferences: SignalPreferences())
        #expect(center.recent.contains { $0.kind == "signal.degraded" },
                "a mysteriously short history is worse than an explained one")
    }

    @Test("preferences flow into the center's rules at construction")
    func preferencesApplied() {
        var rules = RoutingRules.default
        rules.mutedSources.insert(.host)
        let center = AppEnvironment.makeSignalCenter(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("signal-\(UUID().uuidString).sqlite"),
            preferences: SignalPreferences(rules: rules, retention: .default))
        #expect(center.rules.mutedSources.contains(.host))
    }

    @Test("the dispatcher is retained, so deliveries do not silently stop")
    func dispatcherIsRetained() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("signal-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let center = AppEnvironment.makeSignalCenter(storeURL: url,
                                                     preferences: SignalPreferences())
        // SignalCenter holds its deliverer weakly. If the factory did not keep
        // the dispatcher alive, every delivery would become a silent no-op that
        // no test of routing would ever catch.
        #expect(center.deliveryTargetIsAliveForTesting)
    }
}
