import Foundation
import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Persisted root directory for the `@`-mention file index (M7 Slice 5c Task 22).
/// Defaults to the user's home directory until a later folder-picker (Task 22b,
/// not built here) lets the user change it.
struct SageWorkspaceSettings: PersistableDocument {
    static let documentID = "assistant-workspace"
    var workingDirectoryPath: String

    init(workingDirectoryPath: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        self.workingDirectoryPath = workingDirectoryPath
    }
}

/// The composition root, assembled once in `AinkradHostApp.init` and injected
/// via `.environment(_:)`. See State, Persistence & Dependency Injection.md.
@MainActor
@Observable
final class AppEnvironment {
    /// True when the process was launched by the XCTest / swift-testing runner.
    /// `xcodebuild test` hosts the test bundle INSIDE this app, so `@main` →
    /// `bootstrap()` boots the full app before any test runs. This flag gates
    /// launch-time external I/O — the local-model reachability probe loop, MCP
    /// server connect, and LSP autodetect — which under a hosted test run
    /// otherwise hang on 30s network timeouts (Ollama `:11434`) or block on a
    /// TCC permission prompt nobody can dismiss, starving the test bundle of the
    /// main loop. Production launches never set `XCTestConfigurationFilePath`,
    /// so this is `false` in the shipped app and startup is byte-identical.
    static let isRunningUnderTests: Bool =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    let persistence: PersistenceStore
    let secrets: SecretStore
    let registry: BuiltInAppRegistry
    let themeManager: ThemeManager
    let workspaceManager: WorkspaceManager
    let launcherStore: LauncherStore
    let connectionStore: ConnectionStore
    /// Shared per-connection live-discovered models — read by the composer's model
    /// picker AND the Auto router's `candidatesProvider`, so a live-discovered model
    /// can be selected and auto-routed. Curated presets are the fallback only.
    let discoveredModelsStore: DiscoveredModelsStore
    let appStore: AppStoreService
    let appStoreStore: AppStoreStore
    let appIconStore: AppIconStore
    let shortcutStore: ShortcutStore
    let quitCoordinator: QuitCoordinator
    let generalSettingsStore: GeneralSettingsStore
    let appAppearanceStore: AppAppearanceStore
    /// Hoard' own display settings (icon size, metadata columns). Constructed
    /// in `init` from `persistence` rather than threaded through bootstrap's
    /// parameter list — it depends on nothing else.
    let filesSettingsStore: HoardSettingsStore
    /// Tracks open Hoard panes so F5/F6 can resolve "the other pane". Must live
    /// here, not in a pane: host tiling destroys panes, and closing the one you
    /// copied FROM would otherwise take the coordination with it.
    let filesPaneCoordinator: PaneCoordinator
    /// One shared filesystem service for every Hoard pane. M1 had each pane
    /// construct its own; `PaneCoordinator` makes panes talk to each other, so
    /// they need to agree on one.
    let filesSystemService: LocalFileSystemService
    /// The undo stack and engine every Hoard mutation funnels through —
    /// keyboard, context menu, and (from M4) the assistant alike, which is what
    /// makes an assistant-initiated batch rename ⌘Z-able like any other.
    let filesUndoStack: UndoStack
    let filesOperationEngine: FileOperationEngine
    /// Per-repo git status for the Hoard browser. Shelling out to `git`, cached
    /// per repository — see `GitStatusProvider` for why the cache is the design
    /// rather than an optimisation.
    let filesGitStatusProvider: GitStatusProvider
    /// ⌘C/⌘X/⌘V, backed by `NSPasteboard` so it interoperates with the Finder.
    let filesClipboard: HoardClipboard
    /// Sidebar favourites. App-wide rather than per-pane: a folder pinned in
    /// one pane must appear in every pane.
    let filesPinnedRoots: HoardPinnedRoots
    let webSearchSettingsStore: WebSearchSettingsStore
    let mediaSettingsStore: MediaSettingsStore
    /// Sage session-share (M8) — writes self-contained HTML share artifacts
    /// to disk and tracks their metadata, backing the composer's "Share…" flow.
    let sessionShareStore: SessionShareStore
    let skySettingsStore: SkySettingsStore
    let sounds: SoundPlaying
    let agentContextHub: AgentContextRegistryHub
    let agentActionHub: AgentActionRegistryHub
    /// Routes a tapped feed action back to the app that published it.
    let signalEmitterHub: SignalEmitterHub
    /// M7 Slice 6 (Security & Sandboxing): the persisted store of built-in +
    /// user-defined `SandboxProfile`s the router resolves against.
    let sandboxProfileStore: SandboxProfileStore
    /// M7 Slice 6 (Security & Sandboxing): chooses backend + `SandboxProfile`
    /// per trust tier. Stored here (not just a local in `bootstrap()`) so it
    /// outlives the `unowned` reference `RunTerminalTool` holds to it.
    let executionRouter: ExecutionRouter
    /// M7 Slice 6 (Security & Sandboxing, Task 16): Keychain-backed per-provider
    /// cloud credentials (Modal token, etc). Cloud stays opt-in per-Agent
    /// (`AgentExecutionPolicy.allowCloud`) — storing a credential here never by
    /// itself enables cloud routing (see `ExecutionRouter`).
    let cloudCredentialsStore: CloudCredentialsStore
    let agentConfigStore: AgentConfigStore
    let agentPermissionStore: AgentPermissionStore
    let agentContextSettingsStore: AgentContextSettingsStore
    let agentContextService: AgentContextService
    let agentStore: AgentStore
    let agentSession: AgentSession
    /// M7 Slice 2 (MCP) — owns configured servers' live connections; its discovered
    /// tools feed `agentToolRegistry.dynamicTools` and its trust decisions feed
    /// `agentSession`'s `mcpTrust` closure. See `bootstrap()`.
    let mcpServerRegistry: MCPServerRegistry
    /// M7 Slice 2 (LSP) — owns live language-server connections; feeds
    /// `EditQuality` advisory diagnostics/formatting for `EditFileTool`. See
    /// `bootstrap()` for the non-blocking first-launch autodetect seed.
    let lspServerRegistry: LSPServerRegistry
    /// M7 Slice 3 (Autonomy) Task 11 wiring: the per-session edit ledger `agentSession`
    /// (and every background run's headless session) journals into, the subagent
    /// fan-out coordinator `spawn_subagent` delegates through, and the Runs monitor's
    /// observable queue/active/history engine — retained here so `RunsPanelView` and
    /// any future surface can bind to the SAME live `RunManager` a background run
    /// updates.
    let editJournal: EditJournal
    let subagentCoordinator: SubagentCoordinator
    let runManager: RunManager
    /// Persisted history of Sage chats, surfaced by the block's history sidebar.
    let assistantSessionStore: SageSessionStore
    /// M7 Slice 3b (Autonomy: scheduling/triggers) — the persisted `AgentSchedule`s
    /// the `ScheduleUIView` create/edit list reads/writes, `scheduleRunner` (time
    /// triggers) and `fileChangeWatcher`+`triggerDispatcher` (event triggers) fire
    /// against. Retained here (not just a bootstrap local) for the same reason as
    /// `runManager` above: `ScheduleUIView` and any future surface must bind to the
    /// SAME live store a background trigger updates.
    let scheduleStore: ScheduleStore
    /// M7 Slice 3b: fires enabled `.time` schedules on a 60s tick against `runManager`.
    /// Started once in `bootstrap()`; retained here so it isn't deallocated (which
    /// would invalidate its `Timer`) once `bootstrap()` returns.
    let scheduleRunner: ScheduleRunner
    /// M7 Slice 3b: rate-limited fan-in for event-triggered schedules (file/git
    /// change, webhook) — both `fileChangeWatcher`'s callbacks and (once started)
    /// `WebhookServer` route through `fire(_:)` here.
    let triggerDispatcher: TriggerDispatcher
    /// M7 Slice 3b: FSEvents-backed watcher registered (in `bootstrap()`) for every
    /// enabled `.fileChange`/`.gitChange` schedule, routing `onChange` into
    /// `triggerDispatcher.fire`. Retained so its `FSEventStreamRef`s stay alive.
    let fileChangeWatcher: FileChangeWatcher
    let modelCatalogService: ModelCatalogService
    /// M7 Slice 5b (Model Router / Usage / Failover) runtime wiring.
    let modelCatalog: ModelCatalog
    let modelPriceTable: ModelPriceTable
    let usageTracker: UsageTracker
    let routerOutcomeStore: RouterOutcomeStore
    let modelRouter: ModelRouter
    let runtimeOptionsStore: RuntimeOptionsStore
    let localModelProbe: LocalModelProbe
    /// Async-refreshed reachability cache gating LOCAL candidates in
    /// `candidatesProvider` (bootstrap) — see `LocalModelAvailability`.
    let localModelAvailability: LocalModelAvailability
    let authProfileStore: AuthProfileStore
    /// Subscription OAuth (Task 10): the store the main `agentSession`'s
    /// `credentialResolver` reads a live `.subscription` credential from —
    /// retained here (not just a `bootstrapAgentSessionAndRuns` local) so the
    /// settings UI (Task 11) can drive sign-in/sign-out through the SAME
    /// instance the session resolves credentials against.
    let oauthStore: OAuthCredentialStore
    let commandRegistry: CommandRegistry
    /// The root directory `workspaceFileIndex` was built from — persisted via
    /// `SageWorkspaceSettings`, defaulting to the home directory. Task 22b's
    /// folder-picker will add a setter that persists a new root and rebuilds the
    /// index; not built here.
    let assistantWorkingDirectory: URL
    /// Fuzzy file index over `assistantWorkingDirectory`, backing the `@`-mention
    /// overlay Task 22b builds. Refreshed once asynchronously at bootstrap.
    let workspaceFileIndex: WorkspaceFileIndex
    /// The assistant memory subsystem (M7 Slice 1). `nil` when the FTS index
    /// couldn't be opened at launch — the app degrades to memory-less rather
    /// than crashing (see `bootstrap()`).
    let memoryService: MemoryService?
    /// Structured user facts (name, what to call you, role, timezone) collected
    /// by the first-run "You" step. Non-optional even when `memoryService` is
    /// `nil`: it only needs the memory files, not the FTS index. Every write
    /// re-projects into `USER.md`, so the assistant reads these facts.
    let userProfileStore: UserProfileStore
    /// The Skills subsystem (M7 Slice 4): active-skill registry backing
    /// `use_skill`/`propose_skill`, the skill-index context source, and the
    /// skill `/name` slash commands.
    let skillRegistry: SkillRegistry
    /// CRUD over `/name` → skill-name command bindings; registers its
    /// `SlashCommand`s into `commandRegistry` at bootstrap.
    let skillCommandStore: SkillCommandStore
    /// Watches `Skills/` on disk (Task 14) and reloads `skillRegistry` when the
    /// user adds/edits/removes a `SKILL.md` outside the app — retained for the
    /// process lifetime so its `DispatchSource` stays alive; see `bootstrap()`
    /// for where it's started.
    let skillWatcher: SkillWatcher
    /// M7 Slice 7: menu-bar (status item) presence — derived run summary + open
    /// state — wrapping `runManager` via `RunManagerMenuBarAdapter`. Constructed
    /// in `bootstrap()` alongside `runManager` so both share the same instance.
    let menuBarPresence: MenuBarPresence
    /// M7 Slice 7 (Live Scry): the spatial-card store `ScryApp`'s pane binds
    /// to and `scry_render` (appended to the shared `agentToolRegistry` in
    /// `bootstrap()`) mutates — same one-instance-shared-everywhere pattern as
    /// `runManager`/`scheduleStore` above.
    let canvasStore: ScryStore
    /// Terminal streaming (Task 7): the store `run_terminal`'s live stdout/stderr
    /// lands in and `AgentTurnTimelineView` reads for the running tool card — one
    /// instance shared by the main `agentSession`'s `RunTerminalTool` and the
    /// Sage timeline, same pattern as `canvasStore` above.
    let toolStreamStore: ToolStreamStore
    /// Tool Hooks (M8 assistant-tool-hooks Task 5): persisted, observable CRUD
    /// over user-authored PreToolUse/PostToolUse hooks — one instance shared
    /// by the main `agentSession`'s `ToolHookRunner` and the settings surface
    /// (Task 6) that binds to it, same pattern as `toolStreamStore`/
    /// `canvasStore` above.
    let toolHooksStore: ToolHooksStore
    /// File-based custom `/name` slash commands (project + user Markdown files) —
    /// registered into `commandRegistry` after skill commands at bootstrap; see
    /// `resyncCustomCommands`.
    let customCommandStore: CustomCommandStore
    /// Watches the user custom-commands directory and reloads/re-registers
    /// `customCommandStore`'s bindings when a file is added/edited/removed —
    /// retained for the process lifetime so its `DispatchSource` stays alive;
    /// see `bootstrapAgentSessionAndRuns` for where it's started.
    let customCommandWatcher: CustomCommandWatcher
    /// M7 Slice 8 (Voice): push-to-talk + file-transcription facade. Constructed
    /// after `agentSession` (both in `bootstrap()` and here) so
    /// `attachSession(_:)` can wire voice auto-send through the real session's
    /// `send(_:)` — voice is not a privileged input channel.
    let voiceService: VoiceService
    /// Multi-channel Task 5: persisted config (enable flag + port) for the optional
    /// remote channel; the bearer token lives in `SecretStore`, never here. The
    /// settings surface binds to this SAME instance the launch-time
    /// `applyEnabledState()` read from.
    let remoteChannelSettingsStore: RemoteChannelSettingsStore
    /// Multi-channel Task 5: owns the `WebhookServer` lifecycle for the remote
    /// channel. Fail-closed — only listens (127.0.0.1) when enabled AND a token
    /// exists. Retained here so the settings surface and menu-bar presence read
    /// the SAME live `status`.
    let remoteChannelService: RemoteChannelService
    /// The Signal feed. Built in `finalizeBootstrap` (it needs the sound engine
    /// and the window state), so `var`/optional.
    var signalCenter: SignalCenter?
    /// Whether notifications make a sound, and how loud. Held here because
    /// Settings binds to it, and built in `finalizeBootstrap` alongside the
    /// second sound engine it drives.
    var notificationSounds: NotificationSoundStore?
    /// Routes a clicked macOS banner back to its event. Held here so
    /// `AinkradApp.install(_:into:)` can hand it to the app delegate on both
    /// boot and environment swap, exactly as it does the socket server.
    var signalBannerResponder: SignalBannerResponder?
    /// Where the user last left the feed. Built in the bootstrap beside the
    /// preferences store it sits next to on disk.
    var signalViewStateStore: SignalViewStateStore?
    /// Token → source for external emitters. Held here because Settings needs
    /// it to mint and revoke, not only bootstrap.
    var signalTokens: SignalTokenRegistry?
    /// What each open pane reports it is showing. Not optional: an empty
    /// registry is meaningful (no app reports locators) and a nil one would
    /// make every call site check for something that is always there.
    let paneLocators = PaneLocatorRegistry()
    /// Declared and approved cross-app subscriptions (generation 10).
    var signalSubscriptions: SignalSubscriptionRegistry?
    /// App ids whose declared subscriptions the user has not answered yet.
    /// Drives the consent prompt; empty is the normal state.
    var pendingSubscriptionApprovals: [String] = []
    /// External ingress. Optional because a socket that cannot bind must
    /// degrade to "no external ingress", never to a failed launch.
    var signalSocketServer: SignalSocketServer?
    /// Shared toast stack, presented over the window by `RootView`.
    let signalToasts = SignalToastModel()
    /// True while the bell's dropdown is open. Separate from the overlay flag:
    /// the dropdown is a glance, the overlay is the feed.
    var isSignalDropdownPresented = false
    /// True while the in-window feed island is open.
    var isSignalFeedPresented = false
    /// Skill `/name` command names currently registered into `commandRegistry`
    /// — tracked so `resyncSkillCommands()` (Task 13) knows exactly which
    /// entries to drop before re-registering the current binding set, without
    /// ever touching a builtin name it didn't register itself.
    private var registeredSkillCommandNames: Set<String> = []
    /// Blocking first-run gate. Unlike every other overlay this is not dismissible:
    /// the workspace renders behind it but nothing in it can be reached.
    var isSetupPresented = false
    /// True when the wizard was opened from Settings rather than raised as a
    /// gate. Read once by `SetupOverlayView` when it builds its coordinator.
    var isSetupReplay = false

    /// Setup steps the user was let past without satisfying, mirrored from the
    /// `SetupDocument` marker so the workspace can be honest about it without
    /// re-reading persistence on every redraw.
    ///
    /// Written in exactly two places — launch (`AinkradApp.init`) and the
    /// wizard's closing step (`SetupDoneStepView.finish`) — which are the only
    /// two moments the marker changes. `.providers` here means the assistant
    /// cannot work, and drives the persistent banner in `RootView`.
    var deferredSetupSteps: Set<SetupStep> = []

    /// True while the app is running against a provisional Home that the user has
    /// not yet chosen. Nothing authored may be written until this clears.
    var isProvisionalHome = false

    var isLauncherPresented = false
    var isWorkspaceOverviewPresented = false
    var isSettingsPresented = false
    var isAppStorePresented = false
    var isQuickAskPresented = false
    #if DEBUG
    /// Component Gallery — DEBUG-only, reachable via the Launcher's system
    /// action row. Never compiled into release builds (AIN — Slice 1b Task 8).
    var isComponentGalleryPresented = false
    #endif
    /// The id of a `.overlay`-presentation plugin app currently summoned as a
    /// floating host overlay (Slice 3), or `nil` when none is shown. Cleared
    /// automatically when any app opens (see the launch-hub open handler in
    /// `bootstrap()`), so an overlay never lingers behind a newly-opened pane.
    var presentedOverlayAppID: String? = nil
    /// Tracks the host window's full-screen state — set by
    /// `KeyboardShortcutMonitor.MonitoringView` from `NSWindow`'s full-screen
    /// notifications (AIN-109). Drives `HUDBar`'s full-screen status bar;
    /// unused in windowed mode.
    var isFullScreen = false
    /// In full screen the top bar (traffic lights + status + workspace dots)
    /// stays hidden and reveals only while the pointer is at the top edge,
    /// Xcode-style — set by `MonitoringView`'s mouse-moved monitor. Ignored
    /// in windowed mode, where the bar is always shown.
    var isTopBarRevealed = false

    init(
        persistence: PersistenceStore,
        secrets: SecretStore,
        registry: BuiltInAppRegistry,
        themeManager: ThemeManager,
        workspaceManager: WorkspaceManager,
        launcherStore: LauncherStore,
        connectionStore: ConnectionStore,
        discoveredModelsStore: DiscoveredModelsStore,
        appStore: AppStoreService,
        appStoreStore: AppStoreStore,
        appIconStore: AppIconStore,
        shortcutStore: ShortcutStore,
        quitCoordinator: QuitCoordinator,
        generalSettingsStore: GeneralSettingsStore,
        appAppearanceStore: AppAppearanceStore,
        webSearchSettingsStore: WebSearchSettingsStore,
        mediaSettingsStore: MediaSettingsStore,
        sessionShareStore: SessionShareStore,
        skySettingsStore: SkySettingsStore,
        sounds: SoundPlaying,
        agentContextHub: AgentContextRegistryHub,
        agentActionHub: AgentActionRegistryHub,
        signalHub: SignalEmitterHub,
        sandboxProfileStore: SandboxProfileStore,
        executionRouter: ExecutionRouter,
        cloudCredentialsStore: CloudCredentialsStore,
        agentConfigStore: AgentConfigStore,
        agentPermissionStore: AgentPermissionStore,
        agentContextSettingsStore: AgentContextSettingsStore,
        agentContextService: AgentContextService,
        agentStore: AgentStore,
        agentSession: AgentSession,
        mcpServerRegistry: MCPServerRegistry,
        lspServerRegistry: LSPServerRegistry,
        editJournal: EditJournal,
        subagentCoordinator: SubagentCoordinator,
        runManager: RunManager,
        assistantSessionStore: SageSessionStore,
        scheduleStore: ScheduleStore,
        scheduleRunner: ScheduleRunner,
        triggerDispatcher: TriggerDispatcher,
        fileChangeWatcher: FileChangeWatcher,
        modelCatalogService: ModelCatalogService,
        modelCatalog: ModelCatalog,
        modelPriceTable: ModelPriceTable,
        usageTracker: UsageTracker,
        routerOutcomeStore: RouterOutcomeStore,
        modelRouter: ModelRouter,
        runtimeOptionsStore: RuntimeOptionsStore,
        localModelProbe: LocalModelProbe,
        localModelAvailability: LocalModelAvailability,
        authProfileStore: AuthProfileStore,
        oauthStore: OAuthCredentialStore,
        commandRegistry: CommandRegistry,
        assistantWorkingDirectory: URL,
        workspaceFileIndex: WorkspaceFileIndex,
        memoryService: MemoryService?,
        userProfileStore: UserProfileStore,
        skillRegistry: SkillRegistry,
        skillWatcher: SkillWatcher,
        skillCommandStore: SkillCommandStore,
        menuBarPresence: MenuBarPresence,
        canvasStore: ScryStore,
        toolStreamStore: ToolStreamStore,
        toolHooksStore: ToolHooksStore,
        customCommandStore: CustomCommandStore,
        customCommandWatcher: CustomCommandWatcher,
        voiceService: VoiceService,
        remoteChannelSettingsStore: RemoteChannelSettingsStore,
        remoteChannelService: RemoteChannelService
    ) {
        self.persistence = persistence
        self.secrets = secrets
        self.registry = registry
        self.themeManager = themeManager
        self.workspaceManager = workspaceManager
        self.launcherStore = launcherStore
        self.connectionStore = connectionStore
        self.discoveredModelsStore = discoveredModelsStore
        self.appStore = appStore
        self.appStoreStore = appStoreStore
        self.appIconStore = appIconStore
        self.shortcutStore = shortcutStore
        self.quitCoordinator = quitCoordinator
        self.generalSettingsStore = generalSettingsStore
        self.appAppearanceStore = appAppearanceStore
        self.filesSettingsStore = HoardSettingsStore(persistence: persistence)
        self.filesPaneCoordinator = PaneCoordinator()
        self.filesSystemService = LocalFileSystemService()
        let filesUndoStack = UndoStack(persistence: persistence)
        self.filesUndoStack = filesUndoStack
        self.filesOperationEngine = FileOperationEngine(
            mutator: LocalFileMutator(), trash: SystemTrashService(), undoStack: filesUndoStack)
        self.filesGitStatusProvider = GitStatusProvider(fileSystem: LocalFileSystemService())
        self.filesClipboard = HoardClipboard()
        self.filesPinnedRoots = HoardPinnedRoots(persistence: persistence)
        self.webSearchSettingsStore = webSearchSettingsStore
        self.mediaSettingsStore = mediaSettingsStore
        self.sessionShareStore = sessionShareStore
        self.skySettingsStore = skySettingsStore
        self.sounds = sounds
        self.agentContextHub = agentContextHub
        self.agentActionHub = agentActionHub
        self.signalEmitterHub = signalHub
        self.sandboxProfileStore = sandboxProfileStore
        self.executionRouter = executionRouter
        self.cloudCredentialsStore = cloudCredentialsStore
        self.agentConfigStore = agentConfigStore
        self.agentPermissionStore = agentPermissionStore
        self.agentContextSettingsStore = agentContextSettingsStore
        self.agentContextService = agentContextService
        self.agentStore = agentStore
        self.agentSession = agentSession
        self.mcpServerRegistry = mcpServerRegistry
        self.lspServerRegistry = lspServerRegistry
        self.editJournal = editJournal
        self.subagentCoordinator = subagentCoordinator
        self.runManager = runManager
        self.assistantSessionStore = assistantSessionStore
        self.scheduleStore = scheduleStore
        self.scheduleRunner = scheduleRunner
        self.triggerDispatcher = triggerDispatcher
        self.fileChangeWatcher = fileChangeWatcher
        self.modelCatalogService = modelCatalogService
        self.modelCatalog = modelCatalog
        self.modelPriceTable = modelPriceTable
        self.usageTracker = usageTracker
        self.routerOutcomeStore = routerOutcomeStore
        self.modelRouter = modelRouter
        self.runtimeOptionsStore = runtimeOptionsStore
        self.localModelProbe = localModelProbe
        self.localModelAvailability = localModelAvailability
        self.authProfileStore = authProfileStore
        self.oauthStore = oauthStore
        self.commandRegistry = commandRegistry
        self.assistantWorkingDirectory = assistantWorkingDirectory
        self.workspaceFileIndex = workspaceFileIndex
        self.memoryService = memoryService
        self.userProfileStore = userProfileStore
        self.skillRegistry = skillRegistry
        self.skillWatcher = skillWatcher
        self.skillCommandStore = skillCommandStore
        self.menuBarPresence = menuBarPresence
        self.canvasStore = canvasStore
        self.toolStreamStore = toolStreamStore
        self.toolHooksStore = toolHooksStore
        self.customCommandStore = customCommandStore
        self.customCommandWatcher = customCommandWatcher
        self.voiceService = voiceService
        self.remoteChannelSettingsStore = remoteChannelSettingsStore
        self.remoteChannelService = remoteChannelService
        // Seeds `registeredSkillCommandNames` with whatever bootstrap already
        // registered (see the loop right after `commandRegistry` is built),
        // so the very first `resyncSkillCommands()` call — triggered by a
        // bind/unbind from the Skills manager UI — knows what to drop.
        self.registeredSkillCommandNames = Set(skillCommandStore.slashCommands(registry: skillRegistry).map(\.name))
    }

    /// True when this app currently has a live shell, by EITHER presentation
    /// route: a tiled pane in any workspace, or the floating overlay
    /// (`.overlay` apps never get a `tileLayout` block — see the launch-hub
    /// open handler in `finalizeBootstrap`).
    ///
    /// This composition lives here because `AppEnvironment` is the only type
    /// that owns both halves. Backs the app-hosted MCP activator's "do I need
    /// to launch this app first?" check — answering `false` for an already-
    /// presented overlay app would make every tool call against it wait out the
    /// launch timeout and fail, for a server that was reachable the whole time.
    func isAppOpen(_ appID: String) -> Bool {
        workspaceManager.isAppTiled(appID) || presentedOverlayAppID == appID
    }

    /// Re-syncs the live `commandRegistry` with the current
    /// `skillCommandStore` bindings. Bootstrap (`bootstrap()` below) only
    /// registers skill `/name` commands once, at launch — a bind/unbind made
    /// afterward via the Skills manager UI (Task 13) would otherwise sit
    /// invisibly in `skillCommandStore` until the next relaunch. Call this
    /// after every bind/unbind so `/name` starts/stops working immediately.
    /// Never touches a builtin: it only unregisters names THIS method
    /// previously registered, then re-registers the current binding set
    /// (`slashCommands(registry:)` independently filters out any name that
    /// collides with a builtin, as defense in depth).
    func resyncSkillCommands() {
        for name in registeredSkillCommandNames {
            commandRegistry.unregister(name: name)
        }
        let commands = skillCommandStore.slashCommands(registry: skillRegistry)
        for command in commands {
            commandRegistry.register(command)
        }
        registeredSkillCommandNames = Set(commands.map(\.name))
    }

    /// Assembles a real `AppEnvironment` backed by the file document store and
    /// the Keychain. Every on-disk location is derived from `home` — there is no
    /// default and no fallback, so no subsystem can compute a storage path of
    /// its own. Tests pass a throwaway `Home` (`TestHome.make()`).
    /// `defaults` is the legacy import source (`.standard`).
    static func bootstrap(home: Home, defaults: UserDefaults = .standard) -> AppEnvironment {
        let sp0 = AinkradSignposts.begin(AinkradSignposts.launch, "boot-core-stores")
        let (
            persistence, secrets, registry, themeManager, workspaceManager, pluginDirs,
            pluginDataRoot, retainedDataRoot, agentContextHub, agentActionHub, pluginLaunchHub,
            signalHub,
            appAppearanceStore, webSearchSettingsStore, mediaSettingsStore, sessionShareStore, loader, mcpConfigStore, skillsRoot, appStore, appStoreStore, appIconStore,
            generalSettingsStore, skySettingsStore, sounds, connectionStore, discoveredModelsStore,
            assistantDocuments
        ) = bootstrapCoreStores(home: home, defaults: defaults)
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
            sandboxProfileStore, cloudCredentialsStore, executionRouter, agentTools, mcpServerRegistry, canvasStore,
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
            fileChangeWatcher, assistantWorkingDirectory, workspaceFileIndex, agentSession, voiceService, menuBarPresence,
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
            launcherStore: LauncherStore(registry: registry, workspaceManager: workspaceManager, appAppearanceStore: appAppearanceStore),
            connectionStore: connectionStore,
            discoveredModelsStore: discoveredModelsStore,
            appStore: appStore,
            appStoreStore: appStoreStore,
            appIconStore: appIconStore,
            shortcutStore: ShortcutStore(persistence: persistence),
            quitCoordinator: QuitCoordinator(persistence: persistence, terminator: AppKitTerminationReplier()),
            generalSettingsStore: generalSettingsStore,
            appAppearanceStore: appAppearanceStore,
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
            canvasStore: canvasStore,
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

    #if DEBUG
    /// Set only by `preview()`, so this instance's `deinit` knows to remove
    /// the temp directory and defaults suite `preview()` created for it.
    /// `nil` for every environment built by real `bootstrap()` callers (the
    /// app itself, and every non-preview test) — those never own throwaway
    /// storage and must never have it cleaned up from under them.
    /// `nonisolated(unsafe)`: written once by `preview()` right after init,
    /// read once by `deinit` (which Swift always runs `nonisolated`, even on
    /// a `@MainActor` class). Never mutated concurrently — a preview
    /// environment is never shared across threads before it's torn down.
    private nonisolated(unsafe) var previewTeardown: (() -> Void)?

    /// A fully-wired `AppEnvironment` for previews and tests that need real
    /// descriptor→store bindings (e.g. `HostSettingsCatalog`) without a real
    /// app launch. Each call gets its own temp directory and an isolated
    /// `UserDefaults` suite, so callers never see another call's state and
    /// nothing touches the developer's real `~/Library/Application Support`
    /// or `.standard` defaults. Reuses the production `bootstrap()` wiring
    /// rather than a bespoke stub graph — `isRunningUnderTests` already gates
    /// the network/TCC-prompting I/O (model probe, MCP connect, LSP
    /// autodetect) when hosted under `xcodebuild test`, so this is safe and
    /// fast in that context; call sites outside tests should expect that
    /// gating to relax and real I/O to occur.
    ///
    /// Cleanup is tied to the returned instance's lifetime (`deinit` below)
    /// rather than, say, a shared/reused environment, because reuse would
    /// mean two tests running back-to-back could observe each other's
    /// mutations — the exact cross-test contamination every later task's
    /// catalog tests depend on NOT happening. Per-call isolation is kept;
    /// only the on-disk/on-suite footprint is reclaimed, once the caller
    /// drops its last reference.
    static func preview() -> AppEnvironment {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AinkradPreview-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "com.ainkrad.preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        // A per-call temp vault, which is also what keeps `preview()` out of the
        // real Keychain: `Home.keychainServiceName` derives the Keychain service
        // from the vault path, so this throwaway vault gets a throwaway namespace
        // (see `Home+KeychainService.swift`). Several test suites use `preview()`,
        // so that is load-bearing, not incidental.
        let home = Home(vaultRoot: root.appendingPathComponent("vault", isDirectory: true),
                        cacheRoot: root.appendingPathComponent("cache", isDirectory: true))
        let environment = bootstrap(home: home, defaults: defaults)
        environment.previewTeardown = {
            try? FileManager.default.removeItem(at: root)
            UserDefaults().removePersistentDomain(forName: suiteName)
        }
        return environment
    }

    nonisolated deinit {
        previewTeardown?()
    }
    #endif
}
