import AinkradHostRuntime
import Foundation

/// Installs / uninstalls MCP-server catalog items. No download and no `dlopen`:
/// installing records a disabled+untrusted `MCPServerConfig` (secret key names
/// only) plus an entry in `InstalledPluginsDocument` so the App Store lists it.
/// The user enables/trusts and supplies secrets in the MCP manager (Task 14).
@MainActor
final class MCPServerInstaller {
    private let configStore: MCPServerConfigStore
    private let persistence: PersistenceStore

    init(configStore: MCPServerConfigStore, persistence: PersistenceStore) {
        self.configStore = configStore
        self.persistence = persistence
    }

    /// Validates the catalog entry, then upserts an `MCPServerConfig` (secret
    /// KEY NAMES only — never values) and records installed state. Re-running
    /// on an already-installed entry is safe: `configStore.upsert` replaces the
    /// existing config by `id` (no duplicate), and since the replacement is
    /// always built `enabled: false, trusted: false` from the descriptor
    /// (never touching Keychain), any secret values the user already stored
    /// under `mcp/<id>/<key>` are untouched — only the metadata document is
    /// rewritten.
    func install(_ entry: CatalogEntry) throws {
        guard entry.isValidMCPEntry, let mcp = entry.mcp else {
            throw AppStoreError.invalidBundle("invalid MCP catalog entry \(entry.appID)")
        }
        configStore.upsert(
            MCPServerConfig(
                id: entry.appID, displayName: entry.displayName, transport: mcp.transport,
                command: mcp.command, args: mcp.args, url: mcp.url,
                envKeys: mcp.envKeys, headerKeys: mcp.headerKeys,
                enabled: false, trusted: false))
        var doc = persistence.load(InstalledPluginsDocument.self) ?? InstalledPluginsDocument()
        doc.installed[entry.appID] = .init(version: entry.version, sourceRepo: entry.sourceRepo)
        persistence.save(doc)
    }

    /// Removes the config (and, via `MCPServerConfigStore.remove`, its
    /// Keychain secrets) plus the installed-state entry — symmetric with
    /// `PluginInstaller.uninstall`.
    func uninstall(appID: String) throws {
        var doc = persistence.load(InstalledPluginsDocument.self) ?? InstalledPluginsDocument()
        guard doc.installed[appID] != nil else { throw AppStoreError.notInstalled(appID) }
        configStore.remove(id: appID)
        doc.installed[appID] = nil
        persistence.save(doc)
    }
}
