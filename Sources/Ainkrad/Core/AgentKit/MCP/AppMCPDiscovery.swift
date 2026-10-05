import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/MCP/AppMCPDiscovery.swift
import Foundation

/// Synthesizes an `MCPServerConfig` for every installed app that publishes an
/// MCP server.
///
/// Discovery is STATIC: it reads `RegisteredApp.mcpServerFactory`, which the
/// loader populated from an `as?` cast on the app type. No app has to be open,
/// and nothing is probed — an earlier design that probed a live server could
/// not see a closed app at all. Nothing here launches an app, spawns a process,
/// or awaits anything, so it is safe on the main-actor launch path.
@MainActor
enum AppMCPDiscovery {
    /// Adds a config for each MCP-publishing app, refreshing the display name
    /// of ones already known. The user's `enabled`/`trusted` choices are the
    /// user's — a refresh never resets them. Configs for other transports are
    /// never touched.
    /// Configs for apps that are gone are pruned: an uninstalled app would
    /// otherwise leave a permanent `.inProcess` card in MCP settings, stuck at
    /// "failed", with no way to delete it (an app row has no remove button).
    /// Only `.inProcess` configs are ours to prune — a stdio/httpSSE config is
    /// the user's own and is never touched, matched or not.
    static func refresh(apps: [RegisteredApp], into store: MCPServerConfigStore) {
        let installed = Set(apps.map(\.id))
        for config in store.all()
        where config.transport == .inProcess
            && !installed.contains(config.appID ?? config.id)
        {
            store.remove(id: config.id)
        }

        for app in apps where app.mcpServerFactory != nil {
            if let existing = store.config(id: app.id) {
                // An id collision with a user-configured stdio/httpSSE server is
                // the user's config, not ours to overwrite — skip rather than
                // convert it to `.inProcess`.
                guard existing.transport == .inProcess else { continue }
                var updated = existing
                updated.displayName = app.displayName
                updated.appID = app.id
                store.upsert(updated)
            } else {
                store.upsert(
                    MCPServerConfig(
                        id: app.id,
                        displayName: app.displayName,
                        transport: .inProcess,
                        // On by default so an installed app's tools are usable,
                        // but NOT trusted — first-party still hits the approval
                        // gate until the user says otherwise.
                        enabled: true,
                        trusted: false,
                        appID: app.id))
            }
        }
    }
}
