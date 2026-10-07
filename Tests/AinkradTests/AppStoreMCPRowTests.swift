import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

/// Mirrors `FakeAppStoreService` from `AppStoreStoreTests.swift` (file-private
/// there) so this suite doesn't depend on cross-file visibility of a test fake.
@MainActor
private final class FakeMCPAppStoreService: AppStoreServing {
    var cachedCatalog: [CatalogEntry] = []
    var installedResult: [String: InstalledPluginsDocument.Entry] = [:]
    var updatesResult: [CatalogEntry] = []

    func refreshCatalog() async -> [CatalogEntry] { cachedCatalog }
    func install(appID: String) async throws {
        let v = cachedCatalog.first { $0.appID == appID }?.version ?? "1.0.0"
        installedResult[appID] = .init(version: v, sourceRepo: "o/\(appID)")
    }
    func update(appID: String) async throws { try await install(appID: appID) }
    func uninstall(appID: String) throws { installedResult[appID] = nil }
    func installedApps() -> [String: InstalledPluginsDocument.Entry] { installedResult }
    func availableUpdates() -> [CatalogEntry] { updatesResult }
    func hasRetainedData(appID: String) -> Bool { false }
    func restoreRetainedData(appID: String) {}
    func discardRetainedData(appID: String) {}
}

@Suite("App Store MCP rows")
@MainActor
struct AppStoreMCPRowTests {
    private func mcpEntry(_ id: String = "web-search") -> CatalogEntry {
        CatalogEntry(
            appID: id, displayName: "Web Search", icon: "i", description: "d",
            version: "1", apiVersion: 0, downloadURL: URL(string: "https://e/n")!, sha256: "",
            sourceRepo: "o/r", kind: .mcpServer,
            mcp: MCPCatalogDescriptor(transport: .stdio, command: "npx", envKeys: ["API_KEY"]))
    }

    @Test func mcpCatalogEntryProducesMCPRow() {
        let fake = FakeMCPAppStoreService()
        fake.cachedCatalog = [mcpEntry()]
        let store = AppStoreStore(
            service: fake,
            registry: BuiltInAppRegistry(persistence: InMemoryPersistenceStore()))
        store.reloadRows()
        #expect(store.rows.first(where: { $0.id == "web-search" })?.kind == .mcpServer)
    }

    @Test func installedMCPEntryIsStillFlaggedMCPServer() async {
        let fake = FakeMCPAppStoreService()
        fake.cachedCatalog = [mcpEntry()]
        let store = AppStoreStore(
            service: fake,
            registry: BuiltInAppRegistry(persistence: InMemoryPersistenceStore()))
        store.reloadRows()
        await store.install("web-search")
        let row = store.rows.first { $0.id == "web-search" }
        #expect(row?.kind == .mcpServer)
        #expect(row?.status == .installed)
        #expect(row?.isManaged == true)
    }

    @Test func nonMCPCatalogEntryIsUnaffected() {
        let fake = FakeMCPAppStoreService()
        fake.cachedCatalog = [
            CatalogEntry(
                appID: "notes", displayName: "Notes", icon: "i",
                description: "d", version: "1", apiVersion: 0, downloadURL: URL(string: "https://e/n")!,
                sha256: "", sourceRepo: "o/r")
        ]
        let store = AppStoreStore(
            service: fake,
            registry: BuiltInAppRegistry(persistence: InMemoryPersistenceStore()))
        store.reloadRows()
        #expect(store.rows.first(where: { $0.id == "notes" })?.kind == .plugin)
    }
}
