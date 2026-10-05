import AinkradAppKit
import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

private final class FakeDocs: PluginDocumentStore {
    var storage: [String: Data] = [:]
    func data(forKey key: String) -> Data? { storage[key] }
    func setData(_ data: Data?, forKey key: String) { storage[key] = data }
}

private struct LegacyDoc: PersistableDocument, Equatable {
    static let documentID = "terminal-settings"
    var shell: String = "/bin/bash"
}

@Suite("TerminalSettingsMigration")
struct TerminalSettingsMigrationTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "com.ainkrad.tests.\(UUID().uuidString)")!
    }

    @Test("copies legacy payload bytes into the scoped store, once")
    func copiesLegacy() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let legacy = FileDocumentStore(rootURL: dir)
        legacy.save(LegacyDoc())
        let scoped = FakeDocs()
        let d = defaults()

        TerminalSettingsMigration.runIfNeeded(
            legacyRawPayload: { legacy.rawPayloadData(forID: $0) },
            scoped: scoped, defaults: d)

        let bytes = try #require(scoped.data(forKey: "terminal-settings"))
        #expect((try? JSONDecoder().decode(LegacyDoc.self, from: bytes)) == LegacyDoc())
        #expect(d.bool(forKey: TerminalSettingsMigration.flagKey))
    }

    @Test("does nothing when the flag is already set")
    func skipsWhenFlagged() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let legacy = FileDocumentStore(rootURL: dir)
        legacy.save(LegacyDoc())
        let scoped = FakeDocs()
        let d = defaults()
        d.set(true, forKey: TerminalSettingsMigration.flagKey)

        TerminalSettingsMigration.runIfNeeded(
            legacyRawPayload: { legacy.rawPayloadData(forID: $0) },
            scoped: scoped, defaults: d)
        #expect(scoped.data(forKey: "terminal-settings") == nil)
    }

    @Test("with no legacy doc, sets the flag and writes nothing")
    func noLegacyDoc() {
        let scoped = FakeDocs()
        let d = defaults()
        TerminalSettingsMigration.runIfNeeded(legacyRawPayload: { _ in nil }, scoped: scoped, defaults: d)
        #expect(scoped.data(forKey: "terminal-settings") == nil)
        #expect(d.bool(forKey: TerminalSettingsMigration.flagKey))
    }

    @Test("never overwrites an existing scoped doc")
    func doesNotOverwrite() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let legacy = FileDocumentStore(rootURL: dir)
        legacy.save(LegacyDoc())
        let scoped = FakeDocs()
        scoped.setData(Data("existing".utf8), forKey: "terminal-settings")
        TerminalSettingsMigration.runIfNeeded(
            legacyRawPayload: { legacy.rawPayloadData(forID: $0) },
            scoped: scoped, defaults: defaults())
        #expect(scoped.data(forKey: "terminal-settings") == Data("existing".utf8))
    }
}
