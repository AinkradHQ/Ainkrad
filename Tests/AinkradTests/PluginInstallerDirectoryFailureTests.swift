import AinkradAppKit
import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

/// The installer's data moves when the directory they move INTO can't be
/// created (a read-only parent). The user's plugin data must never be lost:
/// it stays where it was, and the operation around it still completes.
@MainActor
struct PluginInstallerDirectoryFailureTests {
    /// A temp root holding a read-only `ro/` folder. The caller's `body` runs
    /// with the folder locked; it is unlocked again before cleanup.
    private func withReadOnlyFolder(_ body: (_ root: URL, _ readOnly: URL) throws -> Void) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let readOnly = root.appendingPathComponent("ro")
        try FileManager.default.createDirectory(at: readOnly, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnly.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnly.path)
            try? FileManager.default.removeItem(at: root)
        }
        try body(root, readOnly)
    }

    private func installer(
        pluginDataDir: URL, retainedDataDir: URL, root: URL, persistence: PersistenceStore
    ) -> PluginInstaller {
        PluginInstaller(
            http: StubHTTPClient(responses: [:]), unzipper: DittoUnzipper(),
            pluginsDir: root.appendingPathComponent("Plugins"),
            pluginDataDir: pluginDataDir, retainedDataDir: retainedDataDir,
            persistence: persistence, registry: BuiltInAppRegistry(persistence: InMemoryPersistenceStore()),
            loadBundle: { _ in .failure(PluginRejection(reason: "unused")) })
    }

    @Test("uninstall still completes when the retained area can't be created, and leaves the data in place")
    func uninstallWithUncreatableRetainedArea() throws {
        try withReadOnlyFolder { root, readOnly in
            let persistence = InMemoryPersistenceStore()
            var doc = InstalledPluginsDocument()
            doc.installed["notes"] = .init(version: "1.0.0", sourceRepo: "o/notes")
            persistence.save(doc)
            let inst = installer(
                pluginDataDir: root.appendingPathComponent("PluginData"),
                retainedDataDir: readOnly.appendingPathComponent("RetainedPluginData"),
                root: root, persistence: persistence)
            let live = root.appendingPathComponent("PluginData/notes")
            try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
            try Data("hello".utf8).write(to: live.appendingPathComponent("settings.bin"))

            try inst.uninstall(appID: "notes")

            #expect(persistence.load(InstalledPluginsDocument.self)?.installed["notes"] == nil)
            #expect((try? Data(contentsOf: live.appendingPathComponent("settings.bin"))) == Data("hello".utf8))
            #expect(!inst.hasRetainedData(appID: "notes"))
        }
    }

    @Test("restore keeps the retained data when the live area can't be created")
    func restoreWithUncreatableLiveArea() throws {
        try withReadOnlyFolder { root, readOnly in
            let retainedDir = root.appendingPathComponent("RetainedPluginData")
            let inst = installer(
                pluginDataDir: readOnly.appendingPathComponent("PluginData"),
                retainedDataDir: retainedDir, root: root, persistence: InMemoryPersistenceStore())
            let retained = retainedDir.appendingPathComponent("notes")
            try FileManager.default.createDirectory(at: retained, withIntermediateDirectories: true)
            try Data("keep".utf8).write(to: retained.appendingPathComponent("settings.bin"))

            inst.restoreRetainedData(appID: "notes")

            #expect(inst.hasRetainedData(appID: "notes"))
            #expect((try? Data(contentsOf: retained.appendingPathComponent("settings.bin"))) == Data("keep".utf8))
        }
    }
}
