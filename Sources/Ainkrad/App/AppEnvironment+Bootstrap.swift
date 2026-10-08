import AinkradAppKit
import AinkradHostRuntime
import Foundation
import SwiftUI

extension AppEnvironment {
    /// Assembles a real `AppEnvironment` backed by the file document store and
    /// the Keychain. Every on-disk location is derived from `home` — there is no
    /// default and no fallback, so no subsystem can compute a storage path of
    /// its own. Tests pass a throwaway `Home` (`TestHome.make()`).
    /// `defaults` is the legacy import source (`.standard`).
    /// - Parameter systemAppearance: the live system light/dark source; tests pass a stub so a theme
    ///   with both variants does not follow the Mac running the suite.
    static func bootstrap(
        home: Home, defaults: UserDefaults = .standard,
        systemAppearance: any SystemAppearanceSource = LiveSystemAppearance()
    ) -> AppEnvironment {
        let sp0 = AinkradSignposts.begin(AinkradSignposts.launch, "boot-core-stores")
        let (
            persistence, secrets, registry, themeManager, workspaceManager, pluginDirs,
            pluginDataRoot, retainedDataRoot, agentContextHub, agentActionHub, pluginLaunchHub,
            signalHub,
            appAppearanceStore, webSearchSettingsStore, mediaSettingsStore, sessionShareStore, loader, mcpConfigStore,
            skillsRoot, appStore, appStoreStore, appIconStore,
            generalSettingsStore, skySettingsStore, sounds, connectionStore, discoveredModelsStore,
            assistantDocuments
        ) = bootstrapCoreStores(home: home, defaults: defaults, systemAppearance: systemAppearance)
        AinkradSignposts.end(AinkradSignposts.launch, "boot-core-stores", sp0)

        let sp1 = AinkradSignposts.begin(AinkradSignposts.launch, "boot-agentkit-core")
        let (
            streamingHTTP, agentConfigStore, agentContextSettingsStore, agentContextService,
            agentPermissionStore, memoryService, userProfileStore, lspServerRegistry, editJournal,
            skillRegistry, skillCommandStore, skillWatcher
        ) = bootstrapAgentKitCore(
            persistence: persistence, workspaceManager: workspaceManager, agentContextHub: agentContextHub,
            skillsRoot: skillsRoot, home: home)
        AinkradSignposts.end(AinkradSignposts.launch, "boot-agentkit-core", sp1)

        let sp2 = AinkradSignposts.begin(AinkradSignposts.launch, "boot-execution-and-tools")
        let (
            sandboxProfileStore, cloudCredentialsStore, executionRouter, agentTools, mcpServerRegistry, scryStore,
            signalReadAccess, toolStreamStore, terminalController
        ) = bootstrapExecutionAndTools(
            home: home,
            persistence: persistence, secrets: secrets, lspServerRegistry: lspServerRegistry,
            editJournal: editJournal, workspaceManager: workspaceManager, agentActionHub: agentActionHub,
            agentContextHub: agentContextHub, memoryService: memoryService, mcpConfigStore: mcpConfigStore,
            appRegistry: registry, pluginLaunchHub: pluginLaunchHub, skillRegistry: skillRegistry,
            permissionMode: { [weak agentPermissionStore] in agentPermissionStore?.mode ?? .ask })
        AinkradSignposts.end(AinkradSignposts.launch, "boot-execution-and-tools", sp2)

        let sp3 = AinkradSignposts.begin(AinkradSignposts.launch, "boot-model-routing")
        let (
            modelCatalogService, agentStore, modelCatalog, modelPriceTable, routerOutcomeStore, modelRouter,
            usageTracker, runtimeOptionsStore, localModelProbe, localModelAvailability, authProfileStore,
            candidatesProvider, commandRegistry
        ) = bootstrapModelRouting(
            persistence: persistence, assistantDocuments: assistantDocuments,
            secrets: secrets, connectionStore: connectionStore,
            discoveredModelsStore: discoveredModelsStore)
        AinkradSignposts.end(AinkradSignposts.launch, "boot-model-routing", sp3)

        let sp4 = AinkradSignposts.begin(AinkradSignposts.launch, "boot-session-and-runs")
        let (
            subagentCoordinator, runManager, assistantSessionStore, scheduleStore, scheduleRunner, triggerDispatcher,
            fileChangeWatcher, assistantWorkingDirectory, workspaceFileIndex, agentSession, voiceService,
            menuBarPresence,
            oauthStore, toolHooksStore, customCommandStore, customCommandWatcher,
            remoteChannelSettingsStore, remoteChannelService
        ) = bootstrapAgentSessionAndRuns(
            home: home,
            persistence: persistence, secrets: secrets, streamingHTTP: streamingHTTP, connectionStore: connectionStore,
            agentConfigStore: agentConfigStore, agentContextService: agentContextService,
            agentPermissionStore: agentPermissionStore, agentStore: agentStore, editJournal: editJournal,
            memoryService: memoryService, modelRouter: modelRouter, executionRouter: executionRouter,
            candidatesProvider: candidatesProvider, usageTracker: usageTracker,
            runtimeOptionsStore: runtimeOptionsStore, commandRegistry: commandRegistry,
            authProfileStore: authProfileStore, localModelProbe: localModelProbe,
            agentActionHub: agentActionHub, agentTools: agentTools, mcpServerRegistry: mcpServerRegistry,
            skillRegistry: skillRegistry, skillCommandStore: skillCommandStore,
            toolStreamStore: toolStreamStore, terminalController: terminalController)
        AinkradSignposts.end(AinkradSignposts.launch, "boot-session-and-runs", sp4)

        let environment = AppEnvironment(
            persistence: persistence,
            secrets: secrets,
            registry: registry,
            themeManager: themeManager,
            workspaceManager: workspaceManager,
            launcherStore: LauncherStore(
                registry: registry, workspaceManager: workspaceManager, appAppearanceStore: appAppearanceStore),
            connectionStore: connectionStore,
            discoveredModelsStore: discoveredModelsStore,
            appStore: appStore,
            appStoreStore: appStoreStore,
            appIconStore: appIconStore,
            shortcutStore: ShortcutStore(persistence: persistence),
            quitCoordinator: QuitCoordinator(persistence: persistence, terminator: AppKitTerminationReplier()),
            generalSettingsStore: generalSettingsStore,
            appAppearanceStore: appAppearanceStore,
            pluginLaunchHub: pluginLaunchHub,
            webSearchSettingsStore: webSearchSettingsStore,
            mediaSettingsStore: mediaSettingsStore,
            sessionShareStore: sessionShareStore,
            skySettingsStore: skySettingsStore,
            sounds: sounds,
            agentContextHub: agentContextHub,
            agentActionHub: agentActionHub, signalHub: signalHub,
            sandboxProfileStore: sandboxProfileStore,
            executionRouter: executionRouter,
            cloudCredentialsStore: cloudCredentialsStore,
            agentConfigStore: agentConfigStore,
            agentPermissionStore: agentPermissionStore,
            agentContextSettingsStore: agentContextSettingsStore,
            agentContextService: agentContextService,
            agentStore: agentStore,
            agentSession: agentSession,
            mcpServerRegistry: mcpServerRegistry,
            lspServerRegistry: lspServerRegistry,
            editJournal: editJournal,
            subagentCoordinator: subagentCoordinator,
            runManager: runManager,
            assistantSessionStore: assistantSessionStore,
            scheduleStore: scheduleStore,
            scheduleRunner: scheduleRunner,
            triggerDispatcher: triggerDispatcher,
            fileChangeWatcher: fileChangeWatcher,
            modelCatalogService: modelCatalogService,
            modelCatalog: modelCatalog,
            modelPriceTable: modelPriceTable,
            usageTracker: usageTracker,
            routerOutcomeStore: routerOutcomeStore,
            modelRouter: modelRouter,
            runtimeOptionsStore: runtimeOptionsStore,
            localModelProbe: localModelProbe,
            localModelAvailability: localModelAvailability,
            authProfileStore: authProfileStore,
            oauthStore: oauthStore,
            commandRegistry: commandRegistry,
            assistantWorkingDirectory: assistantWorkingDirectory,
            workspaceFileIndex: workspaceFileIndex,
            memoryService: memoryService,
            userProfileStore: userProfileStore,
            skillRegistry: skillRegistry,
            skillWatcher: skillWatcher,
            skillCommandStore: skillCommandStore,
            menuBarPresence: menuBarPresence,
            scryStore: scryStore,
            toolStreamStore: toolStreamStore,
            toolHooksStore: toolHooksStore,
            customCommandStore: customCommandStore,
            customCommandWatcher: customCommandWatcher,
            voiceService: voiceService,
            remoteChannelSettingsStore: remoteChannelSettingsStore,
            remoteChannelService: remoteChannelService
        )

        finalizeBootstrap(
            environment: environment, connectionStore: connectionStore, localModelProbe: localModelProbe,
            localModelAvailability: localModelAvailability, mcpServerRegistry: mcpServerRegistry,
            lspServerRegistry: lspServerRegistry, persistence: persistence, secrets: secrets,
            themeManager: themeManager, agentContextHub: agentContextHub, agentActionHub: agentActionHub,
            signalHub: signalHub, signalReadAccess: signalReadAccess,
            pluginLaunchHub: pluginLaunchHub, appAppearanceStore: appAppearanceStore,
            pluginDataRoot: pluginDataRoot, pluginDirs: pluginDirs, loader: loader, registry: registry,
            workspaceManager: workspaceManager, home: home, defaults: defaults
        )

        return environment
    }
}
