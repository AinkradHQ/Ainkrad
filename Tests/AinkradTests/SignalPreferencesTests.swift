import Testing
import Foundation
import AinkradSignal
@testable import Ainkrad

@Suite("SignalPreferences")
struct SignalPreferencesTests {
    private func makeStore() -> (SignalPreferencesStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("signal-prefs-\(UUID().uuidString).json")
        return (SignalPreferencesStore(url: url), url)
    }

    @Test("defaults are returned when nothing is saved")
    func defaults() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let prefs = store.load()
        #expect(prefs.rules == .default)
        #expect(prefs.retention == .default)
    }

    @Test("saved rules survive a round trip, including muted sources and overrides")
    func roundTrip() {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        var rules = RoutingRules.default
        rules.mutedSources.insert(.app(appID: "raven"))
        rules.sourceKindOverrides[SourceKind(source: .host, kind: "run.finished")] = [.feed, .toast]
        store.save(SignalPreferences(rules: rules, retention: RetentionPolicy(maxAgeDays: 7, maxEvents: 500)))

        let loaded = SignalPreferencesStore(url: url).load()
        #expect(loaded.rules.mutedSources.contains(.app(appID: "raven")))
        #expect(loaded.rules.sourceKindOverrides[SourceKind(source: .host, kind: "run.finished")] == [.feed, .toast])
        #expect(loaded.retention.maxAgeDays == 7)
    }

    @Test("a corrupt file falls back to defaults rather than throwing")
    func corruptFileFallsBack() throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)
        #expect(store.load().rules == .default)
    }

    @Test("preferences written before the exemption was removed still load")
    func decodesPreExemptionPreferences() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("signal-prefs-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        // Exactly what M1 wrote, including the flag that no longer exists.
        // `RoutingRules` is Codable with synthesized conformance, so an unknown
        // key is ignored on decode — asserted rather than assumed, because if it
        // were not, every user who changed a notification setting in M1 would
        // silently lose all of them on upgrade.
        let legacy = """
        {"rules":{"mutedSources":[],"sourceOverrides":[],"sourceKindOverrides":[],
        "suppressBannerForHostRuns":true},
        "retention":{"maxAgeDays":7,"maxEvents":500}}
        """
        try Data(legacy.utf8).write(to: url)

        let loaded = SignalPreferencesStore(url: url).load()
        #expect(loaded.retention.maxAgeDays == 7, "the user's retention choice survives")
        #expect(loaded.retention.maxEvents == 500)
        #expect(loaded.rules == .default)
    }
}

@MainActor
@Suite("Signal preferences migration")
struct SignalPreferencesMigrationTests {
    private func url() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("signal-prefs-\(UUID().uuidString).json")
    }

    /// Today's file with the named keys removed — the shape a file written
    /// before those fields existed actually has. Built from the encoder rather
    /// than hand-written, because `sourceOverrides` is keyed by a non-String
    /// enum and encodes as a flat ARRAY: a hand-written fixture guessed that
    /// wrong once already and tested nothing.
    private func legacyFile(without keys: [String],
                            fromRules: Bool = false) throws -> URL {
        let encoded = try JSONEncoder().encode(SignalPreferences())
        var object = try #require(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        if fromRules {
            var rules = try #require(object["rules"] as? [String: Any])
            for key in keys {
                #expect(rules.removeValue(forKey: key) != nil,
                        "\(key) must exist today, or this test proves nothing")
            }
            object["rules"] = rules
        } else {
            for key in keys {
                #expect(object.removeValue(forKey: key) != nil,
                        "\(key) must exist today, or this test proves nothing")
            }
        }
        let target = url()
        try JSONSerialization.data(withJSONObject: object).write(to: target)
        return target
    }

    @Test("a file without the sound field loads with sound ON")
    func absentSoundMeansOn() throws {
        let file = try legacyFile(without: ["sound"])
        defer { try? FileManager.default.removeItem(at: file) }
        let prefs = SignalPreferencesStore(url: file).load()
        // Absent must mean the PREVIOUS behaviour, and that was audible. A
        // migration that silences a user's alerts is indistinguishable from a
        // bug, and they would never think to look here for it.
        #expect(prefs.sound.isEnabled)
    }

    @Test("a file without the Phase 2 control fields loads with no controls set")
    func absentControlsMeanUnconfigured() throws {
        let file = try legacyFile(
            without: ["interruptFloor", "soundOverride", "suppression", "urgentBypass"],
            fromRules: true)
        defer { try? FileManager.default.removeItem(at: file) }
        let prefs = SignalPreferencesStore(url: file).load()
        #expect(prefs.rules.interruptFloor.isEmpty)
        #expect(prefs.rules.soundOverride.isEmpty)
        #expect(prefs.rules.suppression == SuppressionWindow())
        #expect(prefs.rules.urgentBypass.isEmpty)
    }

    @Test("preferences round-trip through the store unchanged")
    func roundTripsThroughDisk() throws {
        var prefs = SignalPreferences()
        prefs.rules.interruptFloor[.app(appID: "raven")] = .warning
        prefs.rules.soundOverride[.host] = .silent
        prefs.rules.suppression.quietStartMinute = 22 * 60
        prefs.rules.suppression.quietEndMinute = 7 * 60
        prefs.sound.volume = 0.35

        let file = url()
        defer { try? FileManager.default.removeItem(at: file) }
        let store = SignalPreferencesStore(url: file)
        store.save(prefs)

        // This is what catches a field added to the struct and forgotten in
        // the hand-written decoder — the failure mode of every decodeIfPresent
        // migration.
        #expect(store.load() == prefs)
    }

    @Test("a corrupt file degrades to defaults rather than refusing to launch")
    func corruptFileDegrades() throws {
        let file = url()
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("{ not json".utf8).write(to: file)
        #expect(SignalPreferencesStore(url: file).load() == SignalPreferences())
    }
}
