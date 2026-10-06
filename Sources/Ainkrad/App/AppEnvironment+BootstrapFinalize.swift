import AinkradAppKit
import AinkradHostRuntime
import Foundation
import SwiftUI

/// `AppEnvironment.bootstrap(home:defaults:)` split into cohesive helpers
/// (M7 finalize Wave D, D2) — this file holds the final, post-construction
/// wiring block: it runs AFTER the real `AppEnvironment` instance exists, so
/// closures can capture it (weakly) directly, mirroring `bootstrap()`'s
/// original order exactly.
extension AppEnvironment {
    static func finalizeBootstrap(
        environment: AppEnvironment,
        connectionStore: ConnectionStore,
        localModelProbe: LocalModelProbe,
        localModelAvailability: LocalModelAvailability,
        mcpServerRegistry: MCPServerRegistry,
        lspServerRegistry: LSPServerRegistry,
        persistence: PersistenceStore,
        secrets: SecretStore,
        themeManager: ThemeManager,
        agentContextHub: AgentContextRegistryHub,
        agentActionHub: AgentActionRegistryHub,
        signalHub: SignalEmitterHub,
        signalReadAccess: SignalReadAccess,
        pluginLaunchHub: PluginLaunchHub,
        appAppearanceStore: AppAppearanceStore,
        pluginDataRoot: URL,
        pluginDirs: [URL],
        loader: PluginLoader,
        registry: BuiltInAppRegistry,
        workspaceManager: WorkspaceManager,
        home: Home,
        defaults: UserDefaults
    ) {
        // Two phases, in this order: the apps phase reports plugin load failures
        // into the feed the signal phase builds.
        let signalCenter = finalizeSignal(
            environment: environment, agentContextHub: agentContextHub, signalHub: signalHub,
            signalReadAccess: signalReadAccess, pluginLaunchHub: pluginLaunchHub, home: home)
        finalizeApps(
            environment: environment, signalCenter: signalCenter, connectionStore: connectionStore,
            localModelProbe: localModelProbe, localModelAvailability: localModelAvailability,
            mcpServerRegistry: mcpServerRegistry, lspServerRegistry: lspServerRegistry,
            persistence: persistence, secrets: secrets, themeManager: themeManager,
            agentContextHub: agentContextHub, agentActionHub: agentActionHub, signalHub: signalHub,
            pluginLaunchHub: pluginLaunchHub, appAppearanceStore: appAppearanceStore,
            pluginDataRoot: pluginDataRoot, pluginDirs: pluginDirs, loader: loader, registry: registry,
            workspaceManager: workspaceManager, defaults: defaults)
    }
}
