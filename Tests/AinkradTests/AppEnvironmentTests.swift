import Testing
import Foundation
@testable import Ainkrad
import AinkradAppKit
import AinkradHostRuntime

private struct NoOpCatalogSource: CatalogSource {
    func fetchCatalog() async throws -> [CatalogEntry] { [] }
}

@Suite("AppEnvironment")
final class AppEnvironmentTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ainkrad-tests-\(UUID().uuidString)")
    deinit { try? FileManager.default.removeItem(at: root) }

    @Test("exposes the exact dependencies it was constructed with")
    @MainActor
    func exposesInjectedDependencies() {
        let persistence = InMemoryPersistenceStore()
        let secrets = InMemorySecretStore()
        let registry = BuiltInAppRegistry(persistence: persistence)
        let themeManager = ThemeManager(persistence: persistence)
        let workspaceManager = WorkspaceManager()
        let appAppearanceStore = AppAppearanceStore(persistence: persistence)
        let launcherStore = LauncherStore(registry: registry, workspaceManager: workspaceManager, appAppearanceStore: appAppearanceStore)
        let connectionStore = ConnectionStore(persistence: persistence, secrets: secrets)
        let catalogService = CatalogService(
            source: NoOpCatalogSource(), persistence: persistence)
        let installer = PluginInstaller(
            http: StubHTTPClient(responses: [:]), unzipper: DittoUnzipper(),
            pluginsDir: FileManager.default.temporaryDirectory.appendingPathComponent("plugins"),
            pluginDataDir: FileManager.default.temporaryDirectory.appendingPathComponent("plugin-data"),
            retainedDataDir: FileManager.default.temporaryDirectory.appendingPathComponent("retained-plugin-data"),
            persistence: persistence, registry: registry, loadBundle: { _ in .failure(PluginRejection(reason: "x")) })
        let mcpInstaller = MCPServerInstaller(
            configStore: MCPServerConfigStore(persistence: persistence, secrets: secrets),
            persistence: persistence)
        let appStore = AppStoreService(catalog: catalogService, installer: installer,
                                        mcpInstaller: mcpInstaller, persistence: persistence)
        let appStoreStore = AppStoreStore(service: appStore, registry: registry)
        let shortcutStore = ShortcutStore(persistence: persistence)
        let quitCoordinator = QuitCoordinator(persistence: persistence, terminator: FakeTerminationReplier())
        let generalSettingsStore = GeneralSettingsStore(persistence: persistence)
        let sounds = SoundEngine(settings: generalSettingsStore)
        let agentContextHub = AgentContextRegistryHub()
        let agentActionHub = AgentActionRegistryHub()
        let sandboxProfileStore = SandboxProfileStore(persistence: persistence)
        let executionRouter = ExecutionRouter(
            profiles: sandboxProfileStore,
            backends: [.host: HostBackend()])
        let cloudCredentialsStore = CloudCredentialsStore(secrets: secrets)
        let agentConfigStore = AgentConfigStore(persistence: persistence)
        let agentContextSettingsStore = AgentContextSettingsStore(persistence: persistence)
        let agentContextService = AgentContextService(hub: agentContextHub, settings: agentContextSettingsStore)
        let agentPermissionStore = AgentPermissionStore(persistence: persistence, currentWorkspaceID: { UUID() })
        let agentStore = AgentStore(persistence: persistence)
        let mcpServerRegistry = MCPServerRegistry(
            configStore: MCPServerConfigStore(persistence: persistence, secrets: secrets))
        let lspServerRegistry = LSPServerRegistry(persistence: persistence)
        let agentSession = AgentSession(
            providerFor: { (connection: Connection) -> LLMProvider in
                switch connection.kind {
                case .claude: return ClaudeProvider(http: URLSessionStreamingHTTPClient())
                case .openAICompatible: return OpenAICompatibleProvider(http: URLSessionStreamingHTTPClient(), baseURL: connection.baseURL)
                case .gemini: return GeminiProvider(http: URLSessionStreamingHTTPClient(), baseURL: connection.baseURL)
                }
            },
            connections: connectionStore,
            config: agentConfigStore,
            context: agentContextService,
            registry: AgentToolRegistry(tools: [ReadFileTool(), EditFileTool()]),
            permissions: agentPermissionStore,
            agents: agentStore
        )
        let editJournal = EditJournal()
        let subagentCoordinator = SubagentCoordinator(
            runner: AgentSessionSubagentRunner(
                allTools: [ReadFileTool()], agents: agentStore,
                router: ModelRouter(catalog: ModelCatalog(), outcomes: RouterOutcomeStore(persistence: persistence)),
                executionRouter: executionRouter,
                candidatesProvider: { [] },
                makeSession: AppEnvironment.makeSubagentSession(
                    providerFor: { _ in ClaudeProvider(http: URLSessionStreamingHTTPClient()) },
                    connections: connectionStore, agentConfigStore: agentConfigStore,
                    agentContextService: agentContextService, agentPermissionStore: agentPermissionStore,
                    agentStore: agentStore, credentialResolver: { _ in [] })))
        let runManager = RunManager(
            persistence: persistence,
            runner: BackgroundRunRunner(makeSession: { _ in agentSession }))
        let assistantSessionStore = SageSessionStore(persistence: persistence)
        let scheduleStore = ScheduleStore(persistence: persistence)
        let triggerDispatcher = TriggerDispatcher(store: scheduleStore, runs: runManager)
        let scheduleRunner = ScheduleRunner(store: scheduleStore, runs: runManager)
        let fileChangeWatcher = FileChangeWatcher()
        let menuBarPresence = MenuBarPresence(runs: RunManagerMenuBarAdapter(manager: runManager))
        let canvasStore = ScryStore(persistence: persistence)
        let toolStreamStore = ToolStreamStore()
        let voiceService = VoiceService(persistence: persistence, connections: connectionStore)
        voiceService.attachSession(agentSession)

        let environment = AppEnvironment(
            persistence: persistence,
            secrets: secrets,
            registry: registry,
            themeManager: themeManager,
            workspaceManager: workspaceManager,
            launcherStore: launcherStore,
            connectionStore: connectionStore,
            discoveredModelsStore: DiscoveredModelsStore(persistence: persistence),
            appStore: appStore,
            appStoreStore: appStoreStore,
            appIconStore: AppIconStore(persistence: persistence, applier: AppKitAppIconApplier(), themeManager: themeManager),
            shortcutStore: shortcutStore,
            quitCoordinator: quitCoordinator,
            generalSettingsStore: generalSettingsStore,
            appAppearanceStore: appAppearanceStore,
            webSearchSettingsStore: WebSearchSettingsStore(persistence: persistence),
            mediaSettingsStore: MediaSettingsStore(persistence: persistence),
            sessionShareStore: SessionShareStore(
                persistence: persistence,
                baseDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("share-\(UUID().uuidString)", isDirectory: true)),
            skySettingsStore: SkySettingsStore(persistence: persistence),
            sounds: sounds,
            agentContextHub: agentContextHub,
            agentActionHub: agentActionHub,
            signalHub: SignalEmitterHub(),
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
            modelCatalogService: ModelCatalogService(http: URLSessionDataHTTPClient()),
            modelCatalog: ModelCatalog(),
            modelPriceTable: ModelPriceTable(),
            usageTracker: UsageTracker(persistence: persistence, prices: ModelPriceTable()),
            routerOutcomeStore: RouterOutcomeStore(persistence: persistence),
            modelRouter: ModelRouter(catalog: ModelCatalog(), outcomes: RouterOutcomeStore(persistence: persistence)),
            runtimeOptionsStore: RuntimeOptionsStore(persistence: persistence),
            localModelProbe: LocalModelProbe(catalog: ModelCatalogService(http: URLSessionDataHTTPClient())),
            localModelAvailability: LocalModelAvailability(),
            authProfileStore: AuthProfileStore(persistence: persistence, secrets: secrets),
            oauthStore: OAuthCredentialStore(persistence: persistence, secrets: secrets,
                                             flow: ClaudeOAuthFlow(clientVersion: "test")),
            commandRegistry: CommandRegistry(builtins: []),
            assistantWorkingDirectory: FileManager.default.homeDirectoryForCurrentUser,
            workspaceFileIndex: WorkspaceFileIndex(root: FileManager.default.homeDirectoryForCurrentUser),
            memoryService: nil,
            userProfileStore: UserProfileStore(
                persistence: persistence,
                memory: MemoryStore(paths: MemoryPaths(
                    root: root.appendingPathComponent("Memory", isDirectory: true)))),
            skillRegistry: SkillRegistry(paths: SkillPaths(root: root.appendingPathComponent("Skills", isDirectory: true))),
            skillWatcher: SkillWatcher(paths: SkillPaths(root: root.appendingPathComponent("Skills", isDirectory: true))) { },
            skillCommandStore: SkillCommandStore(persistence: persistence),
            menuBarPresence: menuBarPresence,
            canvasStore: canvasStore,
            toolStreamStore: toolStreamStore,
            toolHooksStore: ToolHooksStore(persistence: persistence),
            customCommandStore: CustomCommandStore(paths: CustomCommandPaths(
                userRoot: root.appendingPathComponent("Commands", isDirectory: true), projectRoot: nil)),
            customCommandWatcher: CustomCommandWatcher(
                directory: root.appendingPathComponent("Commands", isDirectory: true)) { },
            voiceService: voiceService,
            remoteChannelSettingsStore: RemoteChannelSettingsStore(persistence: persistence, secrets: secrets),
            remoteChannelService: RemoteChannelService(
                settingsStore: RemoteChannelSettingsStore(persistence: persistence, secrets: secrets),
                scheduleStore: scheduleStore, dispatcher: triggerDispatcher, runs: runManager)
        )

        #expect(environment.registry === registry)
        #expect(environment.agentStore === agentStore)
        #expect(environment.agentPermissionStore === agentPermissionStore)
        #expect(environment.agentPermissionStore.mode == .ask)
        #expect(environment.themeManager === themeManager)
        #expect(environment.workspaceManager === workspaceManager)
        #expect(environment.launcherStore === launcherStore)
        #expect(environment.connectionStore === connectionStore)
        #expect(environment.appStore === appStore)
        #expect(environment.appStoreStore === appStoreStore)
        #expect(environment.shortcutStore === shortcutStore)
        #expect(environment.quitCoordinator === quitCoordinator)
        #expect(environment.generalSettingsStore === generalSettingsStore)
        #expect(environment.isFullScreen == false)
    }

    @Test("bootstrap() assembles a working environment on isolated storage, Launcher dismissed")
    @MainActor
    func bootstrapAssemblesRealDependencies() {
        // Isolate the legacy-import source too: bootstrap runs
        // LegacyUserDefaultsMigration against `defaults`, so a shared
        // `.standard` would import stray real `com.ainkrad.app` state and
        // make these assertions non-hermetic on any machine/CI runner.
        let t = TestHome.make("appenv-boot")
        defer { t.cleanup() }
        let environment = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)
        #expect(environment.themeManager.currentTheme == .neonBlue)
        // Terminal is an App Store plugin, not built-in; Sage, Scry and
        // Hoard are the compiled-in built-ins the host registers itself
        // (M5 Phase B, M7 Slice 7, Hoard M1).
        #expect(environment.registry.allApps.map(\.id) == ["sage", "scry", "hoard"])
        #expect(environment.workspaceManager.workspaces.count == 1)
        #expect(environment.isLauncherPresented == false)
        #expect(environment.isSettingsPresented == false)
        #expect(environment.quitCoordinator.isConfirming == false)
        #expect(environment.isFullScreen == false)
        #expect(environment.generalSettingsStore.showFullScreenStatusBar == true)
        // Regression guard for the test-isolation leak: the memory subsystem
        // must be constructed under the injected `Home`, never the real
        // `~/Library/Application Support/<bundle-id>/Memory` — otherwise every
        // `make test` run reindexes the developer's real memory store.
        #expect(environment.memoryService != nil)
        let isolatedMemoryIndex = t.home.shared(.memory).appendingPathComponent("index.sqlite")
        #expect(FileManager.default.fileExists(atPath: isolatedMemoryIndex.path))
    }
}
