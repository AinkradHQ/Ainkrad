import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@MainActor
struct AppStoreServiceTests {
    private func entry(_ id: String, _ v: String) -> CatalogEntry {
        CatalogEntry(
            appID: id, displayName: id, icon: "app", description: "", version: v, apiVersion: 1,
            downloadURL: URL(string: "https://e/\(id).zip")!, sha256: "x", sourceRepo: "o/\(id)")
    }
    struct StubSource: CatalogSource {
        let entries: [CatalogEntry]
        func fetchCatalog() async throws -> [CatalogEntry] { entries }
    }

    @Test("availableUpdates lists catalog entries newer than installed")
    func updates() async {
        let store = InMemoryPersistenceStore()
        var installed = InstalledPluginsDocument()
        installed.installed["hello"] = .init(version: "1.0.0", sourceRepo: "o/hello")
        installed.installed["fresh"] = .init(version: "2.0.0", sourceRepo: "o/fresh")
        store.save(installed)
        let catalog = CatalogService(
            source: StubSource(entries: [entry("hello", "1.1.0"), entry("fresh", "2.0.0")]), persistence: store)
        _ = await catalog.refresh()
        // installer unused in this assertion; a real one is fine.
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore())
        registry.install(builtIn: [])
        let installer = PluginInstaller(
            http: StubHTTPClient(responses: [:]), unzipper: DittoUnzipper(),
            pluginsDir: URL(fileURLWithPath: "/tmp/p"), pluginDataDir: URL(fileURLWithPath: "/tmp/d"),
            retainedDataDir: URL(fileURLWithPath: "/tmp/r"),
            persistence: store, registry: registry, loadBundle: { _ in .failure(PluginRejection(reason: "x")) })
        let mcpInstaller = MCPServerInstaller(
            configStore: MCPServerConfigStore(persistence: store, secrets: InMemorySecretStore()),
            persistence: store)
        let svc = AppStoreService(
            catalog: catalog, installer: installer, mcpInstaller: mcpInstaller,
            persistence: store)
        #expect(svc.availableUpdates().map(\.appID) == ["hello"])
        #expect(svc.installedApps().keys.sorted() == ["fresh", "hello"])
    }
}
