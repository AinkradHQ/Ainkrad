import AinkradAppKit
import AinkradHostRuntime
import CryptoKit
import Foundation
import SwiftUI
import Testing

@testable import Ainkrad

@MainActor
struct PluginLifecycleTests {
    private func sha(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }

    /// Build a real hello.bundle zip at `version` (Info.plist only; the loadBundle
    /// closure fakes the successful in-process load).
    private func bundleZip(dir: URL) throws -> Data {
        let b = dir.appendingPathComponent("hello.bundle/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "AinkradAppID": "hello", "AinkradDisplayName": "Hello",
            "AinkradIconSymbol": "app", "AinkradAPIVersion": AinkradAppKit.apiVersion, "NSPrincipalClass": "X",
            "CFBundleExecutable": "hello",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(
            to: b.appendingPathComponent("Info.plist"))
        let zip = dir.appendingPathComponent("hello.bundle.zip")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", dir.appendingPathComponent("hello.bundle").path, zip.path]
        try p.run()
        p.waitUntilExit()
        return try Data(contentsOf: zip)
    }
    // `author`/non-empty `description` required to pass `StorePolicy` at
    // install intake (see PluginInstallerStorePolicyTests).
    private func entry(_ v: String, url: URL, sha: String) -> CatalogEntry {
        CatalogEntry(
            appID: "hello", displayName: "Hello", icon: "app", description: "Test fixture plugin.", version: v,
            apiVersion: 7, downloadURL: url, sha256: sha, sourceRepo: "o/hello", author: "Ainkrad")
    }
    private func hello(_ url: URL) -> RegisteredApp {
        RegisteredApp(
            id: "hello", displayName: "Hello", icon: "app", isEnabledByDefault: true,
            source: .plugin(url: url, apiVersion: 1), makeRootView: { AnyView(EmptyView()) },
            makeSettingsView: { AnyView(EmptyView()) }, chromeFill: { nil })
    }

    @Test("install → update → disable/enable → uninstall(retain) → reinstall(restore)")
    func fullLifecycle() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let src = root.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let bytes = try bundleZip(dir: src)
        let url = URL(string: "https://e/hello.bundle.zip")!
        let http = StubHTTPClient(responses: [url: .success(bytes)])
        let persistence = InMemoryPersistenceStore()
        let registry = BuiltInAppRegistry(persistence: persistence)
        let pluginData = root.appendingPathComponent("PluginData")
        let installer = PluginInstaller(
            http: http, unzipper: DittoUnzipper(),
            pluginsDir: root.appendingPathComponent("Plugins"),
            pluginDataDir: pluginData,
            retainedDataDir: root.appendingPathComponent("RetainedPluginData"),
            persistence: persistence, registry: registry,
            loadBundle: { u in .success(hello(u)) })

        // 1. Install v1.0.0
        try await installer.install(entry("1.0.0", url: url, sha: sha(bytes)))
        #expect(registry.allApps.map(\.id) == ["hello"])
        #expect(persistence.load(InstalledPluginsDocument.self)?.installed["hello"]?.version == "1.0.0")

        // simulate plugin-written scoped data
        let dataDir = pluginData.appendingPathComponent("hello")
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        try Data("mysetting".utf8).write(to: dataDir.appendingPathComponent("s.bin"))

        // 2. Update to v2.0.0 (newer) — data preserved
        try await installer.update(entry("2.0.0", url: url, sha: sha(bytes)))
        #expect(persistence.load(InstalledPluginsDocument.self)?.installed["hello"]?.version == "2.0.0")
        #expect((try? Data(contentsOf: dataDir.appendingPathComponent("s.bin"))) == Data("mysetting".utf8))

        // 3. Disable then enable
        registry.setEnabled(false, for: "hello")
        #expect(!registry.isEnabled("hello"))
        registry.setEnabled(true, for: "hello")
        #expect(registry.isEnabled("hello"))

        // 4. Uninstall — retains scoped data
        try installer.uninstall(appID: "hello")
        #expect(registry.allApps.isEmpty)
        #expect(persistence.load(InstalledPluginsDocument.self)?.installed["hello"] == nil)
        #expect(!FileManager.default.fileExists(atPath: dataDir.path))
        #expect(installer.hasRetainedData(appID: "hello"))

        // 5. Reinstall with restore — data comes back, app registered again
        installer.restoreRetainedData(appID: "hello")
        try await installer.install(entry("2.0.0", url: url, sha: sha(bytes)))
        #expect(registry.allApps.map(\.id) == ["hello"])
        #expect((try? Data(contentsOf: dataDir.appendingPathComponent("s.bin"))) == Data("mysetting".utf8))
    }
}
