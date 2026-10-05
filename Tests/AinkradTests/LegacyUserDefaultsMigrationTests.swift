import Testing
import Foundation
@testable import Ainkrad
import AinkradHostRuntime

@Suite("LegacyUserDefaultsMigration")
final class LegacyUserDefaultsMigrationTests {
    let suiteName = "com.ainkrad.tests.\(UUID().uuidString)"
    let defaults: UserDefaults
    init() { defaults = UserDefaults(suiteName: suiteName)! }
    deinit { defaults.removePersistentDomain(forName: suiteName) }

    private func seedLegacy() {
        defaults.set(try! JSONEncoder().encode(GlobalSettings(theme: .cyberPurple)),
                     forKey: "global-settings")
        defaults.set(try! JSONEncoder().encode(["terminal": false]), forKey: "registry-enabled-state")
        // Terminal's settings type no longer lives in the host, so the
        // legacy blob is an arbitrary JSON object rather than a concrete type.
        defaults.set(try! JSONEncoder().encode(["defaultShell": "/bin/bash"]), forKey: "terminal-settings")
    }

    @Test("imports legacy values into the persistence store")
    func importsLegacyValues() {
        seedLegacy()
        let store = InMemoryPersistenceStore()
        LegacyUserDefaultsMigration.runIfNeeded(persistence: store, defaults: defaults)

        #expect(store.load(GlobalSettings.self)?.theme == .cyberPurple)
        #expect(store.load(RegistryStateDocument.self)?.enabled == ["terminal": false])
    }

    @Test("a fixture launch imports nothing from the shared UserDefaults domain")
    func fixtureLaunchSkipsImport() {
        seedLegacy()
        let store = InMemoryPersistenceStore()
        LegacyUserDefaultsMigration.runIfNeeded(persistence: store, defaults: defaults, isFixtureLaunch: true)

        #expect(store.load(GlobalSettings.self) == nil)
        #expect(store.load(RegistryStateDocument.self) == nil)
        #expect(store.load(LegacyUserDefaultsMigration.LegacyImportMarker.self) == nil)
    }

    @Test("imports the legacy terminal-settings blob into the file store, type-free")
    func importsTerminalSettingsRawIntoFileStore() throws {
        seedLegacy()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = FileDocumentStore(rootURL: dir)
        defer { try? FileManager.default.removeItem(at: dir) }
        LegacyUserDefaultsMigration.runIfNeeded(persistence: store, defaults: defaults)

        let raw = try #require(store.rawPayloadData(forID: "terminal-settings"))
        let decoded = try JSONDecoder().decode([String: String].self, from: raw)
        #expect(decoded["defaultShell"] == "/bin/bash")
    }

    @Test("does not run a second time once the marker is set")
    func runsOnlyOnce() {
        seedLegacy()
        let store = InMemoryPersistenceStore()
        LegacyUserDefaultsMigration.runIfNeeded(persistence: store, defaults: defaults)

        // Mutate the imported doc, then re-run: a second import would overwrite it.
        store.save(GlobalSettings(theme: .neonBlue))
        LegacyUserDefaultsMigration.runIfNeeded(persistence: store, defaults: defaults)

        #expect(store.load(GlobalSettings.self)?.theme == .neonBlue)
    }

    @Test("no legacy data is a clean no-op that still sets the marker")
    func noLegacyDataNoOp() {
        let store = InMemoryPersistenceStore()
        LegacyUserDefaultsMigration.runIfNeeded(persistence: store, defaults: defaults)
        #expect(store.load(GlobalSettings.self) == nil)
        #expect(store.load(LegacyUserDefaultsMigration.LegacyImportMarker.self)?.didImport == true)
    }
}
