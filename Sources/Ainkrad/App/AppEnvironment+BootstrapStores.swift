import Foundation
import AinkradAppKit
import AinkradHostRuntime

/// `AppEnvironment.bootstrap(home:defaults:)` split into cohesive helpers
/// (M7 finalize Wave D, D2) — this file holds the first two sequential
/// blocks: core persistence/plugin/appearance stores, then the AgentKit
/// core services (memory, LSP, skills, edit journal). Each helper is a pure
/// value-construction step: it takes the already-built deps it needs and
/// returns the values the next block consumes, mirroring `bootstrap()`'s
/// original sequential wiring exactly — no behavior change, only relocation.
extension AppEnvironment {
    /// First block of `bootstrap()`: the file/keychain-backed persistence
    /// layer, the legacy-defaults migration, plugin loading/App Store
    /// plumbing, app appearance/icon/sound stores, and the connection +
    /// discovered-models stores.
    static func bootstrapCoreStores(home: Home, defaults: UserDefaults) -> (
        persistence: PersistenceStore,
        secrets: SecretStore,
        registry: BuiltInAppRegistry,
        themeManager: ThemeManager,
        workspaceManager: WorkspaceManager,
        pluginDirs: [URL],
        pluginDataRoot: URL,
        retainedDataRoot: URL,
        agentContextHub: AgentContextRegistryHub,
        agentActionHub: AgentActionRegistryHub,
        pluginLaunchHub: PluginLaunchHub,
        signalHub: SignalEmitterHub,
        appAppearanceStore: AppAppearanceStore,
        webSearchSettingsStore: WebSearchSettingsStore,
        mediaSettingsStore: MediaSettingsStore,
        sessionShareStore: SessionShareStore,
        loader: PluginLoader,
        mcpConfigStore: MCPServerConfigStore,
        skillsRoot: URL,
        appStore: AppStoreService,
        appStoreStore: AppStoreStore,
        appIconStore: AppIconStore,
        generalSettingsStore: GeneralSettingsStore,
        skySettingsStore: SkySettingsStore,
        sounds: SoundPlaying,
        connectionStore: ConnectionStore,
        discoveredModelsStore: DiscoveredModelsStore,
        assistantDocuments: PersistenceStore
    ) {
        // FIRST, before anything resolves a shared path. v0.16.2 renamed the
        // assistant's vault directory `Assistant/` → `Sage/` along with the app,
        // and every store below is built from `home.shared(_:)`, which now
        // points at the new name. A store constructed before the move would
        // create an empty tree beside the user's real one and silently orphan
        // their connections, memory, skills and session history.
        HomeLayoutMigration.run(vaultRoot: home.vaultRoot)

        let csp0 = AinkradSignposts.begin(AinkradSignposts.launch, "core-a-persistence-keychain-registry")
        let persistence = FileDocumentStore(rootURL: home.shared(.config))
        // Sage's own documents live under `Assistant/`, not `Config/` —
        // `agents.json` and `connections.json` sit directly in it, alongside the
        // `memory/`, `skills/`, `commands/` and `sessions/` subdirectories. That
        // is the published vault layout other apps in the family build against,
        // so it is not something to leave to whichever store happened to be
        // wired first. `VaultMigration`'s relocation table writes to exactly
        // these roots; `VaultLayoutAgreementTests` asserts the two agree.
        let assistantDocuments = FileDocumentStore(rootURL: home.shared(.agents))
        // Secrets NEVER live in the vault — they stay in the Keychain, which is
        // outside the Home entirely. The Keychain *namespace*, though, is derived
        // from the vault (see `Home.keychainServiceName`), so a throwaway vault
        // gets a throwaway service and a test can never read or overwrite the
        // developer's real API keys. Production vaults keep the canonical service.
        let secrets: SecretStore = KeychainSecretStore(service: home.keychainServiceName)

        // One-time import of M1's UserDefaults settings before any store reads.
        LegacyUserDefaultsMigration.runIfNeeded(persistence: persistence, defaults: defaults)

        let registry = BuiltInAppRegistry(persistence: persistence)
        let themeManager = ThemeManager(persistence: persistence)

        let workspaceManager = WorkspaceManager()
        AinkradSignposts.end(AinkradSignposts.launch, "core-a-persistence-keychain-registry", csp0)

        // Plugin loading/App Store plumbing needs to exist before
        // `AppEnvironment` is constructed, since `appStore` is one of its
        // stored dependencies.
        // `DevPlugins/` is an UNMANAGED sideload directory: anything that can
        // write a `.bundle` there gets in-process execution. It is scanned in
        // Debug only (`PluginTrust.scansDevPluginsDirectory`); in Release the
        // sole entry path is a catalog install, which the signature policy
        // below then gates. Order matters — dev last, so a sideloaded build
        // overrides an installed release of the same app (see
        // `PluginLoader.loadAll`'s dedup).
        //
        // Plugin BINARIES are cache: every one of them is re-downloadable from the
        // catalog, so wiping the cache costs a reinstall and nothing more. Plugin
        // DATA is vault: it is what the user authored inside each app.
        let csp1 = AinkradSignposts.begin(AinkradSignposts.launch, "core-b-plugins-appstore")
        let pluginsDir = home.cacheRoot.appendingPathComponent("Plugins", isDirectory: true)
        var pluginDirs = [pluginsDir]
        if PluginTrust.scansDevPluginsDirectory {
            pluginDirs.append(home.cacheRoot.appendingPathComponent("DevPlugins", isDirectory: true))
        }
        // v0.16.0 app rename, bundle half. Must precede PluginLoader below: an
        // installed bundle carries its app id INSIDE its Info.plist, so a
        // v0.7.1 terminal.bundle still declares `terminal` and would register
        // the retired app beside the new one.
        RetiredPluginBundleCleanup.run(pluginsDirectories: pluginDirs)
        let pluginDataRoot = home.vaultRoot.appendingPathComponent("Apps", isDirectory: true)
        // v0.16.0 app rename. MUST precede every HostServicesImpl below: that
        // initialiser resolves `<pluginDataRoot>/<appID>`, so a store built
        // before the move points at a fresh empty directory and silently
        // orphans the user's documents instead of reporting anything.
        AppDataDirectoryRename.run(root: pluginDataRoot)

        // The Signal emitter hub is built here, with the other plugin hubs, and
        // attached to the feed later in `finalizeBootstrap` — the feed needs the
        // sound engine and window state, which do not exist yet, while the
        // plugin host services need the hub now.
        let signalHub = SignalEmitterHub()
        let retainedDataRoot = home.vaultRoot
            .appendingPathComponent("Apps", isDirectory: true)
            .appendingPathComponent(".retained", isDirectory: true)
        let agentContextHub = AgentContextRegistryHub()
        let agentActionHub = AgentActionRegistryHub()
        let pluginLaunchHub = PluginLaunchHub()
        let appAppearanceStore = AppAppearanceStore(persistence: persistence)
        let webSearchSettingsStore = WebSearchSettingsStore(persistence: persistence)
        let mediaSettingsStore = MediaSettingsStore(persistence: persistence)
        let sessionShareStore = SessionShareStore(
            persistence: persistence,
            baseDirectory: home.shared(.sessions).appendingPathComponent("shares", isDirectory: true))
        // Trust policy is chosen by build configuration in ONE place
        // (`PluginTrust`), so the permissive dev policy is compiled out of
        // Release entirely and no wiring mistake can ship it.
        let loader = PluginLoader(signaturePolicy: PluginTrust.policyForCurrentBuild(), minSupportedAPIVersion: GenerationSupport.minSupported) { appID, declaredPresentation in
            HostServicesImpl(appID: appID, dataRootURL: pluginDataRoot,
                             secretStore: secrets, themeManager: themeManager,
                             hub: agentContextHub, actionHub: agentActionHub, launchHub: pluginLaunchHub, signalHub: signalHub,
                             declaredPresentation: declaredPresentation, appAppearanceStore: appAppearanceStore)
        }

        // The app catalog is a single hosted document (the central
        // AinkradCatalog). Adding/updating apps is a catalog edit — no host
        // release. Only this URL is compiled in.
        let catalogURL = URL(string: "https://raw.githubusercontent.com/AinkradHQ/AinkradCatalog/main/catalog.json")!
        let catalogService = CatalogService(
            source: RemoteCatalogSource(url: catalogURL, http: URLSessionHTTPClient()),
            persistence: persistence)
        let installer = PluginInstaller(
            http: URLSessionHTTPClient(), unzipper: DittoUnzipper(),
            // Same directory `pluginDirs`'s first entry scans — the installer must
            // write exactly where the loader reads.
            pluginsDir: pluginsDir,
            pluginDataDir: pluginDataRoot,
            retainedDataDir: retainedDataRoot,
            persistence: persistence, registry: registry,
            loadBundle: { loader.loadBundle(at: $0) })
        // Built here (rather than down by `mcpServerRegistry`, its other user)
        // so `AppStoreService` can be given the same store the MCP install
        // path (Task 13) records configs into — installing an MCP catalog
        // entry from the App Store must show up in the MCP manager and vice
        // versa.
        let mcpConfigStore = MCPServerConfigStore(persistence: persistence, secrets: secrets)
        let mcpInstaller = MCPServerInstaller(configStore: mcpConfigStore, persistence: persistence)
        // Skills are authored content (hand-written SKILL.md files, or installed
        // ones the user then edits) — vault, via the shared `skills` domain. The
        // installer and the registry share this same root: they read/write the
        // same on-disk tree.
        let skillsRoot = home.shared(.skills)
        let skillInstaller = SkillInstaller(
            http: URLSessionHTTPClient(), paths: SkillPaths(root: skillsRoot),
            persistence: persistence)
        let appStore = AppStoreService(catalog: catalogService, installer: installer,
                                       mcpInstaller: mcpInstaller, persistence: persistence,
                                       skillInstaller: skillInstaller)
        let appStoreStore = AppStoreStore(service: appStore, registry: registry)

        let appIconStore = AppIconStore(persistence: persistence,
                                        applier: AppKitAppIconApplier(),
                                        themeManager: themeManager)
        AinkradSignposts.end(AinkradSignposts.launch, "core-b-plugins-appstore", csp1)
        let csp2 = AinkradSignposts.begin(AinkradSignposts.launch, "core-c-settings-and-connections")
        let dsp0 = AinkradSignposts.begin(AinkradSignposts.launch, "c1-appicon-apply")
        themeManager.onThemeChange = { [weak appIconStore] in appIconStore?.applyCurrent() }
        appIconStore.applyCurrent()
        AinkradSignposts.end(AinkradSignposts.launch, "c1-appicon-apply", dsp0)

        let dsp1 = AinkradSignposts.begin(AinkradSignposts.launch, "c2-soundengine-init")
        let generalSettingsStore = GeneralSettingsStore(persistence: persistence)
        let skySettingsStore = SkySettingsStore(persistence: persistence)
        // User-data override dir for AIN-108's sound-pack overrides (e.g. via
        // scripts/install-sao-sounds.sh) — need not exist; SoundEngine falls
        // back to the bundled synth wavs when a given override is absent.
        let soundOverrideDirectory = home.shared(.sounds)
        let sounds = SoundEngine(settings: generalSettingsStore, overrideDirectory: soundOverrideDirectory)
        AinkradSignposts.end(AinkradSignposts.launch, "c2-soundengine-init", dsp1)
        // Plays exactly once per process, here rather than in a view's
        // `.onAppear` (which SwiftUI can re-fire) — `bootstrap()` itself only
        // ever runs once, from `AinkradHostApp.init`.
        let dsp2 = AinkradSignposts.begin(AinkradSignposts.launch, "c3-sound-play-applaunch")
        // Deferred to a later main-actor turn, NOT played inline. Measured:
        // playing it here cost 196 ms on the launch critical path, because the
        // first `play` is what actually spins up the audio stack (the players
        // themselves are lazy now -- see SoundEngine). A launch chime has no
        // business delaying the first frame; it still plays, just after the
        // window is up.
        Task { @MainActor in sounds.play(.appLaunch) }
        AinkradSignposts.end(AinkradSignposts.launch, "c3-sound-play-applaunch", dsp2)

        let dsp3 = AinkradSignposts.begin(AinkradSignposts.launch, "c4-connections-and-models")
        let connectionStore = ConnectionStore(persistence: assistantDocuments, secrets: secrets)

        // Shared per-connection live-discovered models (picker + router candidates).
        // Prune entries for connections that no longer exist so a deleted
        // connection's stale list doesn't linger.
        let discoveredModelsStore = DiscoveredModelsStore(persistence: persistence)
        discoveredModelsStore.prune(keeping: Set(connectionStore.connections.map(\.id)))
        AinkradSignposts.end(AinkradSignposts.launch, "c4-connections-and-models", dsp3)

        AinkradSignposts.end(AinkradSignposts.launch, "core-c-settings-and-connections", csp2)
        return (
            persistence, secrets, registry, themeManager, workspaceManager, pluginDirs,
            pluginDataRoot, retainedDataRoot, agentContextHub, agentActionHub, pluginLaunchHub,
            signalHub,
            appAppearanceStore, webSearchSettingsStore, mediaSettingsStore, sessionShareStore, loader, mcpConfigStore, skillsRoot, appStore, appStoreStore, appIconStore,
            generalSettingsStore, skySettingsStore, sounds, connectionStore, discoveredModelsStore,
            assistantDocuments
        )
    }

    /// Second block of `bootstrap()`: the AgentKit core services — shared
    /// streaming HTTP client, agent config/context/permission stores, the
    /// degrade-don't-crash memory service, the LSP registry, the edit
    /// journal, and the Skills subsystem (registry + command store + watcher).
    static func bootstrapAgentKitCore(
        persistence: PersistenceStore,
        workspaceManager: WorkspaceManager,
        agentContextHub: AgentContextRegistryHub,
        skillsRoot: URL,
        home: Home
    ) -> (
        streamingHTTP: URLSessionStreamingHTTPClient,
        agentConfigStore: AgentConfigStore,
        agentContextSettingsStore: AgentContextSettingsStore,
        agentContextService: AgentContextService,
        agentPermissionStore: AgentPermissionStore,
        memoryService: MemoryService?,
        userProfileStore: UserProfileStore,
        lspServerRegistry: LSPServerRegistry,
        editJournal: EditJournal,
        skillRegistry: SkillRegistry,
        skillCommandStore: SkillCommandStore,
        skillWatcher: SkillWatcher
    ) {
        // AgentKit services (M5 Phase B): one shared streaming HTTP client
        // backs both providers; `AgentSession` is the single read-only chat
        // loop the Sage built-in (and, later, the ambient island) bind to.
        let streamingHTTP = URLSessionStreamingHTTPClient()
        let agentConfigStore = AgentConfigStore(persistence: persistence)
        let agentContextSettingsStore = AgentContextSettingsStore(persistence: persistence)
        let agentContextService = AgentContextService(hub: agentContextHub, settings: agentContextSettingsStore)
        let agentPermissionStore = AgentPermissionStore(
            persistence: persistence,
            currentWorkspaceID: { [weak workspaceManager] in
                workspaceManager?.activeWorkspaceID ?? UUID()
            })
        // Sage memory (M7 Slice 1). Degrade-don't-crash: if the FTS index can't
        // open, the assistant runs memory-less this launch (mirrors FileDocumentStore's
        // corrupt-file quarantine posture) rather than taking the app down.
        // Memory is vault. Its markdown files and profile are authored/curated,
        // and its per-session transcripts are irreplaceable: re-running a prompt
        // produces different output, so a lost transcript is not recoverable.
        // (`index.sqlite` under the same root IS derivable — it is rebuilt from
        // those files — but it is not worth splitting one subsystem's root in
        // two to relocate a rebuildable index.)
        let memoryRoot = home.shared(.memory)
        let memoryService = try? MemoryService(
            paths: MemoryPaths(root: memoryRoot),
            persistence: persistence)

        // The user profile (M7 Slice 1's structured half, wired up by the
        // first-run "You" step). Every `set` re-projects the facts into
        // `USER.md` under the same memory root, so the assistant reads them
        // through its always-loaded set. It needs the file-level `MemoryStore`,
        // not the `MemoryService` facade — and `memoryService` is optional
        // (the FTS index may not open). Rather than make the profile optional
        // too, fall back to a bare `MemoryStore` on the same paths: the
        // profile still persists and `USER.md` is still written; only the
        // search index is missing, which is exactly what "memory-less this
        // launch" already means everywhere else.
        let userProfileStore = UserProfileStore(
            persistence: persistence,
            memory: memoryService?.store ?? MemoryStore(paths: MemoryPaths(root: memoryRoot)))

        // LSP (M7 Slice 2): configured language servers backing `EditFileTool`'s
        // advisory diagnostics/formatting. Uses `LSPServerRegistry.defaultClientFactory`
        // (the real stdio transport factory) — tests inject a stub factory instead so the
        // registry core never spawns a real language-server process. PATH autodetection
        // (below, after `environment` exists) shells out to `which` per known server, so
        // it's seeded from an unawaited `Task`, never here, so a slow/missing binary can't
        // delay launch.
        let lspServerRegistry = LSPServerRegistry(persistence: persistence)

        // M7 Slice 3 (Autonomy) Task 10/11 — the per-session edit ledger `EditFileTool`
        // records into, so a turn's file edits can be undone via `/undo`.
        let editJournal = EditJournal()

        // Skills (M7 Slice 4): construction is synchronous but cheap — `reload()`
        // only lists `Skills/`'s immediate subdirectories and parses their small
        // SKILL.md files, the same order of work `MemoryService`'s FTS open and
        // `PluginLoader.loadAll` already do synchronously at this exact point in
        // bootstrap. A malformed/unreadable skill is skipped and recorded in
        // `loadErrors` (never thrown), so a bad skill can't take launch down.
        // `marketplaceNames` reads the same `InstalledPluginsDocument` plugins use —
        // `SkillInstaller.install` records installed skills there keyed by appID —
        // so a skill installed via the marketplace loads tagged `.marketplace`.
        let skillRegistry = SkillRegistry(
            paths: SkillPaths(root: skillsRoot),
            marketplaceNames: { [weak persistence = persistence] in
                Set((persistence?.load(InstalledPluginsDocument.self)?.installed.keys).map(Array.init) ?? [])
            })
        let skillCommandStore = SkillCommandStore(persistence: persistence)
        // File-watch reload (Task 14): a user editing/adding/removing a
        // SKILL.md directly in Skills/ (outside the app) is picked up live.
        // Captures `skillRegistry` weakly — the watcher never extends its
        // lifetime, only reacts while it's alive.
        let skillWatcher = SkillWatcher(paths: SkillPaths(root: skillsRoot)) { [weak skillRegistry] in
            skillRegistry?.reload()
        }
        skillWatcher.start()

        return (
            streamingHTTP, agentConfigStore, agentContextSettingsStore, agentContextService,
            agentPermissionStore, memoryService, userProfileStore, lspServerRegistry, editJournal,
            skillRegistry, skillCommandStore, skillWatcher
        )
    }
}
