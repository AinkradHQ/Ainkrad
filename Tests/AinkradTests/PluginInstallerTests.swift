import AinkradAppKit
import AinkradHostRuntime
import CryptoKit
import Foundation
import SwiftUI
import Testing

@testable import Ainkrad
@testable import AinkradAppKit

@MainActor
struct PluginInstallerTests {
    // Build a real .bundle dir (Info.plist only) and zip it with ditto; return
    // (zipURL, sha256Hex).
    private func makeBundleZip(appID: String, api: Int = AinkradAppKit.apiVersion, dir: URL) throws -> (URL, String) {
        let bundle = dir.appendingPathComponent("\(appID).bundle/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "AinkradAppID": appID, "AinkradDisplayName": appID, "AinkradIconSymbol": "app",
            "AinkradAPIVersion": api, "NSPrincipalClass": "X", "CFBundleExecutable": appID,
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: bundle.appendingPathComponent("Info.plist"))
        let zip = dir.appendingPathComponent("\(appID).bundle.zip")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", dir.appendingPathComponent("\(appID).bundle").path, zip.path]
        try p.run()
        p.waitUntilExit()
        let hash = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
        return (zip, hash)
    }

    // `author`/non-empty `description` are required for a catalog entry to
    // pass `StorePolicy` (see PluginInstallerStorePolicyTests) — every
    // fixture entry here represents a real store-listed submission, so it
    // must carry them like a real one would.
    private func entry(appID: String, url: URL, sha: String, version: String = "1.0.0") -> CatalogEntry {
        CatalogEntry(
            appID: appID, displayName: appID, icon: "app", description: "Test fixture plugin.", version: version,
            apiVersion: 1, downloadURL: url, sha256: sha, sourceRepo: "o/\(appID)", author: "Ainkrad")
    }

    private func makeInstaller(
        http: HTTPClient, root: URL, registry: BuiltInAppRegistry,
        loadOK: Bool = true
    ) -> PluginInstaller {
        PluginInstaller(
            http: http, unzipper: DittoUnzipper(),
            pluginsDir: root.appendingPathComponent("Plugins"),
            pluginDataDir: root.appendingPathComponent("PluginData"),
            retainedDataDir: root.appendingPathComponent("RetainedPluginData"),
            persistence: InMemoryPersistenceStore(), registry: registry,
            loadBundle: { url in
                loadOK
                    ? .success(
                        RegisteredApp(
                            id: url.deletingPathExtension().lastPathComponent, displayName: "x",
                            icon: "app", isEnabledByDefault: true, source: .plugin(url: url, apiVersion: 1),
                            makeRootView: { AnyView(EmptyView()) }, makeSettingsView: { AnyView(EmptyView()) },
                            chromeFill: { nil }))
                    : .failure(PluginRejection(reason: "load failed"))
            })
    }

    @Test("install places the bundle and registers it")
    func installHappy() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let src = root.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let (zip, sha) = try makeBundleZip(appID: "hello", dir: src)
        let url = URL(string: "https://e/hello.bundle.zip")!
        let http = StubHTTPClient(responses: [url: .success(try Data(contentsOf: zip))])
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore())
        registry.install(builtIn: [])
        let installer = makeInstaller(http: http, root: root, registry: registry)
        try await installer.install(entry(appID: "hello", url: url, sha: sha))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Plugins/hello.bundle").path))
        #expect(registry.allApps.map(\.id) == ["hello"])
    }

    // Note: `.checksumMismatch` is no longer thrown by `install` — the sha
    // compare now runs as one of `StorePolicy`'s checks (see Task 2 /
    // PluginInstallerStorePolicyTests), so a mismatch surfaces as
    // `.invalidBundle` carrying StorePolicy's message, same as any other
    // store-review failure. `.checksumMismatch` stays in `AppStoreError`
    // (untouched enum) but is currently unreachable from `install`.
    @Test("sha256 mismatch rejects and writes nothing")
    func checksumMismatch() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let src = root.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let (zip, _) = try makeBundleZip(appID: "hello", dir: src)
        let url = URL(string: "https://e/hello.bundle.zip")!
        let http = StubHTTPClient(responses: [url: .success(try Data(contentsOf: zip))])
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore())
        registry.install(builtIn: [])
        let installer = makeInstaller(http: http, root: root, registry: registry)
        await #expect(throws: AppStoreError.invalidBundle("Computed sha256 does not match the declared sha256.")) {
            try await installer.install(entry(appID: "hello", url: url, sha: "deadbeef"))
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Plugins/hello.bundle").path))
        #expect(registry.allApps.isEmpty)
    }

    @Test("a bundle whose appID differs from the catalog entry is rejected")
    func appIDMismatch() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let src = root.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let (zip, sha) = try makeBundleZip(appID: "actual", dir: src)
        let url = URL(string: "https://e/x.bundle.zip")!
        let http = StubHTTPClient(responses: [url: .success(try Data(contentsOf: zip))])
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore())
        registry.install(builtIn: [])
        let installer = makeInstaller(http: http, root: root, registry: registry)
        await #expect(throws: (any Error).self) {
            try await installer.install(entry(appID: "claimed", url: url, sha: sha))
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Plugins/claimed.bundle").path))
    }

    @Test("version comparison is numeric per dot-segment")
    func versionCompare() {
        #expect(PluginVersion.isNewer("1.0.1", than: "1.0.0"))
        #expect(PluginVersion.isNewer("1.2", than: "1.1.9"))
        #expect(PluginVersion.isNewer("2.0", than: "1.9.9"))
        #expect(!PluginVersion.isNewer("1.0.0", than: "1.0.0"))
        #expect(!PluginVersion.isNewer("1.0.0", than: "1.0.1"))
    }

    @Test("update replaces on a newer version and refuses same/older")
    func update() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let src = root.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let (zip, sha) = try makeBundleZip(appID: "hello", dir: src)
        let url = URL(string: "https://e/hello.bundle.zip")!
        let http = StubHTTPClient(responses: [url: .success(try Data(contentsOf: zip))])
        let store = InMemoryPersistenceStore()
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore())
        registry.install(builtIn: [])
        let installer = PluginInstaller(
            http: http, unzipper: DittoUnzipper(),
            pluginsDir: root.appendingPathComponent("Plugins"),
            pluginDataDir: root.appendingPathComponent("PluginData"),
            retainedDataDir: root.appendingPathComponent("RetainedPluginData"),
            persistence: store, registry: registry,
            loadBundle: { u in
                .success(
                    RegisteredApp(
                        id: "hello", displayName: "x", icon: "app",
                        isEnabledByDefault: true, source: .plugin(url: u, apiVersion: 1),
                        makeRootView: { AnyView(EmptyView()) }, makeSettingsView: { AnyView(EmptyView()) },
                        chromeFill: { nil }))
            })
        try await installer.install(entry(appID: "hello", url: url, sha: sha, version: "1.0.0"))
        await #expect(throws: AppStoreError.notNewer) {
            try await installer.update(entry(appID: "hello", url: url, sha: sha, version: "1.0.0"))
        }
        try await installer.update(entry(appID: "hello", url: url, sha: sha, version: "1.1.0"))
        #expect(store.load(InstalledPluginsDocument.self)?.installed["hello"]?.version == "1.1.0")
    }

    @Test("uninstall removes files, state, and deregisters")
    func uninstall() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let src = root.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let (zip, sha) = try makeBundleZip(appID: "hello", dir: src)
        let url = URL(string: "https://e/hello.bundle.zip")!
        let http = StubHTTPClient(responses: [url: .success(try Data(contentsOf: zip))])
        let store = InMemoryPersistenceStore()
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore())
        registry.install(builtIn: [])
        let installer = PluginInstaller(
            http: http, unzipper: DittoUnzipper(),
            pluginsDir: root.appendingPathComponent("Plugins"),
            pluginDataDir: root.appendingPathComponent("PluginData"),
            retainedDataDir: root.appendingPathComponent("RetainedPluginData"),
            persistence: store, registry: registry,
            loadBundle: { u in
                .success(
                    RegisteredApp(
                        id: "hello", displayName: "x", icon: "app",
                        isEnabledByDefault: true, source: .plugin(url: u, apiVersion: 1),
                        makeRootView: { AnyView(EmptyView()) }, makeSettingsView: { AnyView(EmptyView()) },
                        chromeFill: { nil }))
            })
        try await installer.install(entry(appID: "hello", url: url, sha: sha))
        try installer.uninstall(appID: "hello")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Plugins/hello.bundle").path))
        #expect(store.load(InstalledPluginsDocument.self)?.installed["hello"] == nil)
        #expect(registry.allApps.isEmpty)
    }
}

@MainActor
struct PluginInstallerErrorPathTests {
    private func sha(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }
    private func entry(_ id: String, url: URL, sha: String) -> CatalogEntry {
        CatalogEntry(
            appID: id, displayName: id, icon: "app", description: "Test fixture plugin.", version: "1.0.0",
            apiVersion: 1, downloadURL: url, sha256: sha, sourceRepo: "o/\(id)", author: "Ainkrad")
    }
    private func installer(
        root: URL, http: HTTPClient, registry: BuiltInAppRegistry,
        persistence: PersistenceStore, loadOK: Bool = true
    ) -> PluginInstaller {
        PluginInstaller(
            http: http, unzipper: DittoUnzipper(),
            pluginsDir: root.appendingPathComponent("Plugins"),
            pluginDataDir: root.appendingPathComponent("PluginData"),
            retainedDataDir: root.appendingPathComponent("RetainedPluginData"),
            persistence: persistence, registry: registry,
            loadBundle: { url in
                loadOK
                    ? .success(
                        RegisteredApp(
                            id: "hello", displayName: "Hello", icon: "app",
                            isEnabledByDefault: true, source: .plugin(url: url, apiVersion: 1),
                            makeRootView: { AnyView(EmptyView()) }, makeSettingsView: { AnyView(EmptyView()) },
                            chromeFill: { nil }))
                    : .failure(PluginRejection(reason: "load failed"))
            })
    }

    @Test("a download failure throws .download and writes nothing")
    func downloadFails() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let url = URL(string: "https://e/hello.bundle.zip")!
        struct Net: Error {}
        let http = StubHTTPClient(responses: [url: .failure(Net())])
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore())
        let persistence = InMemoryPersistenceStore()
        let inst = installer(root: root, http: http, registry: registry, persistence: persistence)
        do {
            try await inst.install(entry("hello", url: url, sha: "x"))
            Issue.record("expected throw")
        } catch let e as AppStoreError {
            if case .download = e {} else { Issue.record("expected .download, got \(e)") }
        } catch { Issue.record("unexpected \(error)") }
        #expect(persistence.load(InstalledPluginsDocument.self)?.installed["hello"] == nil)
        #expect(registry.allApps.isEmpty)
    }

    @Test("bytes that pass sha256 but aren't a zip throw .unpack")
    func unpackFails() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let url = URL(string: "https://e/hello.bundle.zip")!
        let bytes = Data("definitely not a zip".utf8)
        let http = StubHTTPClient(responses: [url: .success(bytes)])
        let inst = installer(
            root: root, http: http, registry: BuiltInAppRegistry(persistence: InMemoryPersistenceStore()),
            persistence: InMemoryPersistenceStore())
        do {
            try await inst.install(entry("hello", url: url, sha: sha(bytes)))
            Issue.record("expected throw")
        } catch let e as AppStoreError {
            if case .unpack = e {} else { Issue.record("expected .unpack, got \(e)") }
        } catch { Issue.record("unexpected \(error)") }
    }

    @Test("a valid zip that contains no readable .bundle throws .invalidBundle")
    func invalidBundle() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        // Zip a plain directory (no Contents/Info.plist) with ditto.
        let src = root.appendingPathComponent("src/notabundle", isDirectory: true)
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try Data("hi".utf8).write(to: src.appendingPathComponent("file.txt"))
        let zip = root.appendingPathComponent("src/x.zip")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", src.path, zip.path]
        try p.run()
        p.waitUntilExit()
        let bytes = try Data(contentsOf: zip)
        let url = URL(string: "https://e/hello.bundle.zip")!
        let http = StubHTTPClient(responses: [url: .success(bytes)])
        let inst = installer(
            root: root, http: http, registry: BuiltInAppRegistry(persistence: InMemoryPersistenceStore()),
            persistence: InMemoryPersistenceStore())
        do {
            try await inst.install(entry("hello", url: url, sha: sha(bytes)))
            Issue.record("expected throw")
        } catch let e as AppStoreError {
            if case .invalidBundle = e {} else { Issue.record("expected .invalidBundle, got \(e)") }
        } catch { Issue.record("unexpected \(error)") }
    }

    @Test("install records state even when live-load fails (effective next launch)")
    func liveLoadFailsButInstalled() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let src = root.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        // Reuse the sibling suite's helper shape: build a valid hello.bundle zip.
        let bundle = src.appendingPathComponent("hello.bundle/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "AinkradAppID": "hello", "AinkradDisplayName": "Hello",
            "AinkradIconSymbol": "app", "AinkradAPIVersion": AinkradAppKit.apiVersion, "NSPrincipalClass": "X",
            "CFBundleExecutable": "hello",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(
            to: bundle.appendingPathComponent("Info.plist"))
        let zip = src.appendingPathComponent("hello.bundle.zip")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", src.appendingPathComponent("hello.bundle").path, zip.path]
        try p.run()
        p.waitUntilExit()
        let bytes = try Data(contentsOf: zip)
        let url = URL(string: "https://e/hello.bundle.zip")!
        let http = StubHTTPClient(responses: [url: .success(bytes)])
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore())
        let persistence = InMemoryPersistenceStore()
        let inst = installer(root: root, http: http, registry: registry, persistence: persistence, loadOK: false)

        try await inst.install(entry("hello", url: url, sha: sha(bytes)))  // succeeds despite load failure

        #expect(persistence.load(InstalledPluginsDocument.self)?.installed["hello"] != nil)  // state recorded
        #expect(registry.allApps.isEmpty)  // not registered
    }
}

@MainActor
struct PluginInstallerRetentionTests {
    private func installer(root: URL) -> PluginInstaller {
        PluginInstaller(
            http: StubHTTPClient(responses: [:]), unzipper: DittoUnzipper(),
            pluginsDir: root.appendingPathComponent("Plugins"),
            pluginDataDir: root.appendingPathComponent("PluginData"),
            retainedDataDir: root.appendingPathComponent("RetainedPluginData"),
            persistence: InMemoryPersistenceStore(),
            registry: BuiltInAppRegistry(persistence: InMemoryPersistenceStore()),
            loadBundle: { _ in .failure(PluginRejection(reason: "unused")) })
    }

    @Test("uninstall moves scoped data to the retained area")
    func uninstallRetains() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let persistence = InMemoryPersistenceStore()
        var doc = InstalledPluginsDocument()
        doc.installed["notes"] = .init(version: "1.0.0", sourceRepo: "o/notes")
        persistence.save(doc)
        let inst = PluginInstaller(
            http: StubHTTPClient(responses: [:]), unzipper: DittoUnzipper(),
            pluginsDir: root.appendingPathComponent("Plugins"),
            pluginDataDir: root.appendingPathComponent("PluginData"),
            retainedDataDir: root.appendingPathComponent("RetainedPluginData"),
            persistence: persistence, registry: BuiltInAppRegistry(persistence: InMemoryPersistenceStore()),
            loadBundle: { _ in .failure(PluginRejection(reason: "unused")) })
        let live = root.appendingPathComponent("PluginData/notes")
        try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: live.appendingPathComponent("settings.bin"))

        try inst.uninstall(appID: "notes")

        #expect(!FileManager.default.fileExists(atPath: live.path))  // live gone
        let retained = root.appendingPathComponent("RetainedPluginData/notes/settings.bin")
        #expect(FileManager.default.fileExists(atPath: retained.path))  // retained present
        #expect((try? Data(contentsOf: retained)) == Data("hello".utf8))  // data intact
        #expect(inst.hasRetainedData(appID: "notes") == true)
    }

    @Test("restore moves retained data back to live; discard deletes it")
    func restoreAndDiscard() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let inst = installer(root: root)
        let retained = root.appendingPathComponent("RetainedPluginData/notes")
        try FileManager.default.createDirectory(at: retained, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: retained.appendingPathComponent("settings.bin"))

        inst.restoreRetainedData(appID: "notes")
        #expect(!inst.hasRetainedData(appID: "notes"))
        #expect(
            (try? Data(contentsOf: root.appendingPathComponent("PluginData/notes/settings.bin"))) == Data("keep".utf8))

        // now seed again and discard
        try FileManager.default.createDirectory(at: retained, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: retained.appendingPathComponent("settings.bin"))
        #expect(inst.hasRetainedData(appID: "notes"))
        inst.discardRetainedData(appID: "notes")
        #expect(!inst.hasRetainedData(appID: "notes"))
    }

    @Test("uninstall with no scoped data does not crash and retains nothing")
    func uninstallNoData() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let persistence = InMemoryPersistenceStore()
        var doc = InstalledPluginsDocument()
        doc.installed["notes"] = .init(version: "1.0.0", sourceRepo: "o/notes")
        persistence.save(doc)
        let inst = PluginInstaller(
            http: StubHTTPClient(responses: [:]), unzipper: DittoUnzipper(),
            pluginsDir: root.appendingPathComponent("Plugins"),
            pluginDataDir: root.appendingPathComponent("PluginData"),
            retainedDataDir: root.appendingPathComponent("RetainedPluginData"),
            persistence: persistence, registry: BuiltInAppRegistry(persistence: InMemoryPersistenceStore()),
            loadBundle: { _ in .failure(PluginRejection(reason: "unused")) })
        try inst.uninstall(appID: "notes")
        #expect(inst.hasRetainedData(appID: "notes") == false)
    }

    @Test("a second uninstall replaces the stale retained copy")
    func uninstallReplacesStale() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let persistence = InMemoryPersistenceStore()
        let inst = PluginInstaller(
            http: StubHTTPClient(responses: [:]), unzipper: DittoUnzipper(),
            pluginsDir: root.appendingPathComponent("Plugins"),
            pluginDataDir: root.appendingPathComponent("PluginData"),
            retainedDataDir: root.appendingPathComponent("RetainedPluginData"),
            persistence: persistence, registry: BuiltInAppRegistry(persistence: InMemoryPersistenceStore()),
            loadBundle: { _ in .failure(PluginRejection(reason: "unused")) })
        let live = root.appendingPathComponent("PluginData/notes")
        func writeLive(_ s: String) throws {
            try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
            try Data(s.utf8).write(to: live.appendingPathComponent("settings.bin"))
        }
        func markInstalled() {
            var d = InstalledPluginsDocument()
            d.installed["notes"] = .init(version: "1", sourceRepo: "o")
            persistence.save(d)
        }

        markInstalled()
        try writeLive("first")
        try inst.uninstall(appID: "notes")
        markInstalled()
        try writeLive("second")
        try inst.uninstall(appID: "notes")

        let retained = root.appendingPathComponent("RetainedPluginData/notes/settings.bin")
        #expect((try? Data(contentsOf: retained)) == Data("second".utf8))
    }
}
