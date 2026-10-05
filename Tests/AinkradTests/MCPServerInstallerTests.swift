import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("MCPServerInstaller")
@MainActor
struct MCPServerInstallerTests {
    private func entry() -> CatalogEntry {
        CatalogEntry(
            appID: "web-search", displayName: "Web Search", icon: "magnifyingglass",
            description: "search", version: "1.0", apiVersion: 0,
            downloadURL: URL(string: "https://e/none")!, sha256: "", sourceRepo: "o/r",
            kind: .mcpServer,
            mcp: MCPCatalogDescriptor(
                transport: .stdio, command: "npx", args: ["-y", "srv"],
                envKeys: ["API_KEY"]))
    }

    @Test func installRecordsConfigAndInstalledState() throws {
        let persistence = InMemoryPersistenceStore()
        let configs = MCPServerConfigStore(persistence: persistence, secrets: InMemorySecretStore())
        let installer = MCPServerInstaller(configStore: configs, persistence: persistence)
        try installer.install(entry())
        let cfg = configs.config(id: "web-search")
        #expect(cfg?.transport == .stdio)
        #expect(cfg?.command == "npx")
        #expect(cfg?.enabled == false)  // installed disabled until user enables/trusts
        #expect(cfg?.envKeys == ["API_KEY"])
        let installed = persistence.load(InstalledPluginsDocument.self)?.installed["web-search"]
        #expect(installed?.version == "1.0")
    }

    @Test func rejectsInvalidMCPEntry() {
        let persistence = InMemoryPersistenceStore()
        let configs = MCPServerConfigStore(persistence: persistence, secrets: InMemorySecretStore())
        let installer = MCPServerInstaller(configStore: configs, persistence: persistence)
        let bad = CatalogEntry(
            appID: "x", displayName: "X", icon: "i", description: "d",
            version: "1", apiVersion: 0, downloadURL: URL(string: "https://e/n")!, sha256: "",
            sourceRepo: "o/r", kind: .mcpServer, mcp: nil)
        #expect(throws: AppStoreError.self) { try installer.install(bad) }
    }

    @Test func uninstallRemovesConfigAndState() throws {
        let persistence = InMemoryPersistenceStore()
        let configs = MCPServerConfigStore(persistence: persistence, secrets: InMemorySecretStore())
        let installer = MCPServerInstaller(configStore: configs, persistence: persistence)
        try installer.install(entry())
        try installer.uninstall(appID: "web-search")
        #expect(configs.config(id: "web-search") == nil)
        #expect(persistence.load(InstalledPluginsDocument.self)?.installed["web-search"] == nil)
    }

    @Test func installIsIdempotent() throws {
        let persistence = InMemoryPersistenceStore()
        let configs = MCPServerConfigStore(persistence: persistence, secrets: InMemorySecretStore())
        let installer = MCPServerInstaller(configStore: configs, persistence: persistence)
        try installer.install(entry())
        // A user-set secret must survive a second install of the same entry.
        configs.setSecret("shh", for: MCPSecretKey(serverID: "web-search", key: "API_KEY"))
        configs.setEnabled(true, for: "web-search")
        try installer.install(entry())
        #expect(configs.all().filter { $0.id == "web-search" }.count == 1)
        #expect(configs.config(id: "web-search")?.envKeys == ["API_KEY"])
        // Re-install must not clobber a value the user already supplied.
        #expect(configs.missingSecrets(for: "web-search").isEmpty)
    }
}
