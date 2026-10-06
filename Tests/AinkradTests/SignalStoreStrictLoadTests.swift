import Foundation
import Testing

@testable import Ainkrad

/// S-ERR-6: a signal file that no longer decodes is set aside, never overwritten by defaults.
@Suite("Signal stores strict load")
struct SignalStoreStrictLoadTests {
    private let seed = Data("{ not json".utf8)

    private func makeDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("signal-strict-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Bytes of every `<name>.corrupt-*` sibling.
    private func setAside(_ file: URL) throws -> [Data] {
        try FileManager.default.contentsOfDirectory(
            at: file.deletingLastPathComponent(), includingPropertiesForKeys: nil
        )
        .filter { $0.lastPathComponent.hasPrefix(file.lastPathComponent + ".corrupt-") }
        .map { try Data(contentsOf: $0) }
    }

    @Test("preferences: a corrupt file is set aside before the next save")
    func preferences() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("prefs.json")
        try seed.write(to: file)
        let store = SignalPreferencesStore(url: file)
        _ = store.load()
        store.save(SignalPreferences())
        #expect(try setAside(file) == [seed])
    }

    @Test("view state: a corrupt file is set aside before the next save")
    func viewState() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("view.json")
        try seed.write(to: file)
        let store = SignalViewStateStore(url: file)
        _ = store.load()
        store.save(SignalViewState())
        #expect(try setAside(file) == [seed])
    }

    @Test("subscriptions: a corrupt file is set aside before the next save")
    func subscriptions() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("subs.json")
        try seed.write(to: file)
        let store = SignalSubscriptionStore(url: file)
        _ = store.load()
        store.save(["raven": ["host/*"]])
        #expect(try setAside(file) == [seed])
    }

    @Test("a corrupt file that cannot be set aside is left untouched and save is refused")
    func unverifiableSetAside() throws {
        let dir = try makeDir()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }
        let file = dir.appendingPathComponent("prefs.json")
        try seed.write(to: file)
        // A read-only folder makes the rename fail.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        let store = SignalPreferencesStore(url: file)
        _ = store.load()
        store.save(SignalPreferences())
        #expect(try Data(contentsOf: file) == seed)
    }
}
