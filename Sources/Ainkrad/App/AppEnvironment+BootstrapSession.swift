import Foundation
import AinkradAppKit
import AinkradHostRuntime

/// `AppEnvironment.bootstrap(home:defaults:)` split into cohesive helpers
/// (M7 finalize Wave D, D2) — this file holds the fifth block: subagent
/// wiring (M7 Slice 3 Task 11), the background/headless run subsystem
/// (Slice 3b Task 21), the schedule/trigger subsystem (Slice 3b), the
/// `@`-mention file index, the main `agentSession`, and `voiceService`. Pure
/// value-construction, mirroring `bootstrap()`'s original order exactly.
extension AppEnvironment {
    /// `web_fetch`/`web_search` are read-class (auto-approve) network-egress
    /// tools. They stay ONLY in the foreground interactive registry; every
    /// UNATTENDED registry (spawned subagents + background/schedule/trigger
    /// runs) excludes them, so no autonomous run performs un-gated network
    /// access. (The foreground main session keeps them, gated by the read
    /// approval policy with the user present.)
    /// `image_generate` also makes paid network calls (image generation API),
    /// so — like web_fetch/web_search — it must be stripped from unattended
    /// registries so an unattended run can't incur paid image generation.
    static func isUnattendedNetworkTool(_ tool: any AgentTool) -> Bool {
        tool is WebFetchTool || tool is WebSearchTool || tool is ImageGenerateTool || tool is VideoGenerateTool
    }

    static func bootstrapAgentSessionAndRuns(
        home: Home,
        persistence: PersistenceStore,
        secrets: SecretStore,
        streamingHTTP: URLSessionStreamingHTTPClient,
        connectionStore: ConnectionStore,
        agentConfigStore: AgentConfigStore,
        agentContextService: AgentContextService,
        agentPermissionStore: AgentPermissionStore,
        agentStore: AgentStore,
        editJournal: EditJournal,
        memoryService: MemoryService?,
        modelRouter: ModelRouter,
        executionRouter: ExecutionRouter,
        candidatesProvider: @escaping @MainActor () -> [RouterCandidate],
        usageTracker: UsageTracker,
        runtimeOptionsStore: RuntimeOptionsStore,
        commandRegistry: CommandRegistry,
        authProfileStore: AuthProfileStore,
        localModelProbe: LocalModelProbe,
        agentActionHub: AgentActionRegistryHub,
        agentTools: [any AgentTool],
        mcpServerRegistry: MCPServerRegistry,
        skillRegistry: SkillRegistry,
        skillCommandStore: SkillCommandStore,
        toolStreamStore: ToolStreamStore,
        terminalController: TerminalProcessController
    ) -> (
        subagentCoordinator: SubagentCoordinator,
        runManager: RunManager,
        assistantSessionStore: SageSessionStore,
        scheduleStore: ScheduleStore,
        scheduleRunner: ScheduleRunner,
        triggerDispatcher: TriggerDispatcher,
        fileChangeWatcher: FileChangeWatcher,
        assistantWorkingDirectory: URL,
        workspaceFileIndex: WorkspaceFileIndex,
        agentSession: AgentSession,
        voiceService: VoiceService,
        menuBarPresence: MenuBarPresence,
        oauthStore: OAuthCredentialStore,
        toolHooksStore: ToolHooksStore,
        customCommandStore: CustomCommandStore,
        customCommandWatcher: CustomCommandWatcher,
        remoteChannelSettingsStore: RemoteChannelSettingsStore,
        remoteChannelService: RemoteChannelService
    ) {
        var agentTools = agentTools

        // NOTE: `agentToolRegistry` (the registry the main `agentSession` and every
        // background run's headless session bind to) is built further below, AFTER
        // `spawn_subagent` is appended to `agentTools` — see the Slice 3 wiring block
        // once the Slice 5b Model Router / `candidatesProvider` it needs exist. Its
        // `dynamicTools` closure surfaces the Slice 2 MCP servers' discovered tools.

        // Single provider-resolution closure, shared by the main `agentSession`, every
        // subagent's child session, and every background run's headless session — one
        // provider construction rule, not three copies that could drift.
        let providerFor: @MainActor (Connection) -> LLMProvider = { connection in
            switch connection.kind {
            case .claude: return ClaudeProvider(http: streamingHTTP)
            case .openAICompatible: return OpenAICompatibleProvider(http: streamingHTTP, baseURL: connection.baseURL)
            case .gemini: return GeminiProvider(http: streamingHTTP, baseURL: connection.baseURL)
            }
        }

        // Subscription OAuth: ONE credential resolver, shared by the main session AND
        // every subagent/background session — so a `.subscription` connection resolves
        // its bearer token everywhere, not just the main interactive session. Created
        // here (above the runners) so the subagent/background session factories can
        // capture it. Also returned so the settings UI drives sign-in through the same
        // `oauthStore` the sessions read their live credential from.
        let oauthStore = OAuthCredentialStore(
            persistence: persistence, secrets: secrets,
            flow: ClaudeOAuthFlow(clientVersion: ClaudeProvider.claudeCodeVersion))
        let credentialResolver: (Connection) async throws -> [ProviderCredential] = { [oauthStore, authProfileStore] connection in
            if connection.authMode == .subscription {
                return [try await oauthStore.liveCredential(for: connection)]
            }
            let keys = authProfileStore.keys(for: connection)
            return (keys.isEmpty ? [""] : keys).map { .apiKey($0) }
        }

        // M7 Slice 3 (Autonomy) Task 11 — wires the whole 3a subsystem live:
        // `spawn_subagent` delegates through `SubagentCoordinator` to the PRODUCTION
        // `AgentSessionSubagentRunner`, whose `makeSession` seam (Task 6's deferred
        // closure) is built here — every child session is UNATTENDED (a requireApproval
        // tool auto-denies rather than parking on a HUD nobody can answer — Task 8's
        // gate) with its router-resolved model PINNED (no router/candidatesProvider
        // passed to the child, so it never re-routes per tool-loop turn).
        let subagentRunner = AgentSessionSubagentRunner(
            allTools: agentTools.filter { !AppEnvironment.isUnattendedNetworkTool($0) }, agents: agentStore, router: modelRouter,
            executionRouter: executionRouter,
            candidatesProvider: candidatesProvider,
            makeSession: AppEnvironment.makeSubagentSession(
                providerFor: providerFor, connections: connectionStore,
                agentConfigStore: agentConfigStore, agentContextService: agentContextService,
                agentPermissionStore: agentPermissionStore, agentStore: agentStore,
                credentialResolver: credentialResolver))
        let subagentCoordinator = SubagentCoordinator(runner: subagentRunner, maxConcurrent: 4)
        agentTools.append(SpawnSubagentTool(coordinator: subagentCoordinator, agents: agentStore))
        // M7 Slice 3b (Autonomy: scheduling/triggers) — Slice 6 is merged on this
        // branch, so `run_tool_script` is wired to the REAL `executionRouter`
        // (never nil): a script always routes through the sandbox backend the
        // router resolves for `.subagent`, never falls back to host.
        agentTools.append(ScriptedBatchTool(executionRouter: executionRouter))

        let agentToolRegistry = AgentToolRegistry(
            tools: agentTools,
            dynamicTools: { [weak mcpServerRegistry] in mcpServerRegistry?.currentTools() ?? [] })

        // M7 Slice 3b Task 21 — every `RunManager`-driven headless run (background,
        // AND schedule/event runs, which enqueue through the SAME `RunManager` /
        // `BackgroundRunRunner` — see the residual-gap note below) is sandboxed at
        // trust tier `.background`: its own tool registry swaps in a `.background`-
        // tier `RunTerminalTool` (the shared `agentToolRegistry`'s instance is fixed
        // at `.mainInteractive`, the only tier ever eligible for `HostBackend`), and
        // its `AgentSession` gets a non-nil `sandboxAllowList` so the compose layer
        // (`SandboxPermissionPolicy.compose`) is always active.
        //
        // RESIDUAL GAP CLOSED (M7 Wave B): `AgentRun.posture` now carries the
        // originating schedule/trigger's `SavedExecutionPosture` end-to-end —
        // `RunManager.enqueue(posture:)` → `AgentRunRunner.execute(posture:)` →
        // `BackgroundRunRunner`'s `makeSession(posture:)` below, which projects
        // `posture.sandboxProfileID` into `ExecutionRouter.resolveProfile` and
        // `posture.permissionMode` into `AgentSession`'s narrowing-only
        // `permissionModeOverride`. A `nil` posture (plain `.chat` runs) or an
        // unresolvable `sandboxProfileID` falls back to the SAME `.background`-
        // tier default as before — fail-closed, never `.host`, never escalation.
        // `scry_render` is EXCLUDED from the background/headless tool list: it's
        // bound to the foreground `canvasStore` (sessionKey "default", the SAME
        // store the `ScryApp` pane reads), so an autonomous background/schedule/
        // trigger run calling it would silently mutate the canvas the user is
        // looking at — a cross-session split-brain. The foreground
        // `agentToolRegistry` above keeps `scry_render`; only this background
        // copy drops it.
        var backgroundAgentTools = agentTools.filter {
            !($0 is ScryRenderTool) && !AppEnvironment.isUnattendedNetworkTool($0)
        }
        if let idx = backgroundAgentTools.firstIndex(where: { $0.name == "run_terminal" }) {
            backgroundAgentTools[idx] = RunTerminalTool(
                actionHub: agentActionHub, router: executionRouter, trustTier: .background)
        }
        let backgroundToolRegistry = AgentToolRegistry(
            tools: backgroundAgentTools,
            dynamicTools: { [weak mcpServerRegistry] in mcpServerRegistry?.currentTools() ?? [] })
        let runManager = RunManager(
            persistence: persistence,
            runner: BackgroundRunRunner(makeSession: { posture in
                // M7 Wave B: resolve THIS run's own sandbox profile from its
                // posture (nil sandboxProfileID == nil policy's behavior below,
                // so a `.chat`/postureless run resolves identically to before).
                let policy = AgentExecutionPolicy(
                    sandboxProfileID: posture?.sandboxProfileID, allowCloud: false, toolAllowList: nil)
                let sandboxProfile = executionRouter.resolveProfile(tier: .background, policy: policy)
                // Narrowing-only: an unrecognized `permissionMode` string (future/
                // corrupt payload) degrades to `nil` (no override) rather than
                // guessing — `AgentSession.effectiveMode()` then simply falls back
                // to the workspace's own mode, never a wider or crashing path.
                let permissionModeOverride = posture.flatMap { AgentPermissionMode(rawValue: $0.permissionMode) }
                let session = AgentSession(
                    providerFor: providerFor, connections: connectionStore, config: agentConfigStore,
                    context: agentContextService, registry: backgroundToolRegistry, permissions: agentPermissionStore,
                    agents: agentStore, editJournal: editJournal, unattended: true,
                    sandboxAllowList: sandboxProfile.toolAllowList, agentAllowList: nil,
                    router: modelRouter, usage: usageTracker, runtime: runtimeOptionsStore,
                    commands: commandRegistry, authProfiles: authProfileStore,
                    candidatesProvider: candidatesProvider,
                    isLocalConnection: { [localModelProbe] connection in localModelProbe.isLocal(connection) },
                    permissionModeOverride: permissionModeOverride)
                session.credentialResolver = credentialResolver   // subscription works in background runs too
                return session
            }),
 maxConcurrent: 2)

        // Persisted history of Sage chats, surfaced by the block's history
        // sidebar (Sage session-history-sidebar Task 4) — one instance shared
        // via `AppEnvironment`, same pattern as `runManager`/`scheduleStore` above.
        // Chat transcripts are `Sage/sessions/` in the published layout, not
        // `Config/`. `SessionShareStore` already roots its exports at
        // `home.shared(.sessions)/shares`, and `VaultMigration` relocates
        // `assistant-sessions.json` to exactly this root.
        let assistantSessionStore = SageSessionStore(
            persistence: FileDocumentStore(rootURL: home.shared(.sessions)))

        // M7 Slice 7: menu-bar presence wraps the SAME `runManager` above via
        // `RunManagerMenuBarAdapter`, so the status-item popover's run list is
        // always in lockstep with the Runs surface and any background trigger.
        let menuBarPresence = MenuBarPresence(runs: RunManagerMenuBarAdapter(manager: runManager))

        // M7 Slice 3b (Autonomy: scheduling/triggers) — the whole subsystem live:
        // `scheduleStore` persists `AgentSchedule`s (`ScheduleUIView`'s create/edit
        // list); `scheduleRunner` fires enabled `.time` schedules on a 60s tick;
        // `triggerDispatcher` fans event triggers (file/git change, webhook) into
        // `runManager`, rate-limited; `fileChangeWatcher` is registered below for
        // every enabled `.fileChange`/`.gitChange` schedule found at launch. A
        // schedule added/enabled later (via `ScheduleUIView`) only starts firing
        // its FSEvents watch on the NEXT launch — this loop is a one-time seed,
        // matching `WorkspaceFileIndex`'s launch-time-only refresh above.
        let scheduleStore = ScheduleStore(persistence: persistence)
        let triggerDispatcher = TriggerDispatcher(store: scheduleStore, runs: runManager)
        let scheduleRunner = ScheduleRunner(store: scheduleStore, runs: runManager)
        let fileChangeWatcher = FileChangeWatcher()
        for schedule in scheduleStore.schedules where schedule.enabled {
            switch schedule.trigger {
            case .fileChange(let path, let glob):
                fileChangeWatcher.watch(scheduleID: schedule.id, path: path, glob: glob) { event in
                    triggerDispatcher.fire(event)
                }
            case .gitChange(let repoPath):
                // PROVISIONAL: prefer a native Git Mage change event if/when one
                // exists; until then, watch `.git` refs via FSEvents.
                fileChangeWatcher.watchGitChange(scheduleID: schedule.id, repoPath: repoPath) { event in
                    triggerDispatcher.fire(event)
                }
            case .time, .webhook:
                break   // .time fires via scheduleRunner; .webhook via WebhookServer (off by default)
            case .unknown:
                break   // forward-compat (M7 Wave B): a future trigger kind this build doesn't know yet
            }
        }
        scheduleRunner.start()

        // Remote channel (multi-channel Task 5): the `WebhookServer` lifecycle is
        // owned by `RemoteChannelService`, NOT constructed eagerly. `applyEnabledState()`
        // is fail-closed — it starts a 127.0.0.1-only listener ONLY when the user
        // previously enabled the channel AND a bearer token exists in `SecretStore`;
        // otherwise it is a no-op (`stop()`), so a fresh install never opens a port.
        // Both stores are retained on `AppEnvironment` so the settings surface binds
        // to the SAME live instances this launch-time call reads from.
        let remoteChannelSettingsStore = RemoteChannelSettingsStore(persistence: persistence, secrets: secrets)
        let remoteChannelService = RemoteChannelService(
            settingsStore: remoteChannelSettingsStore, scheduleStore: scheduleStore,
            dispatcher: triggerDispatcher, runs: runManager)
        remoteChannelService.applyEnabledState()
        // Seed the menu-bar presence once at launch; the settings toggle re-applies
        // state and the view reads `service.status` reactively for its own status line.
        menuBarPresence.remoteChannelListening = RemoteChannelPresence.isListening(remoteChannelService.status)

        // `@`-mention file index (M7 Slice 5c Task 22a wiring; the overlay UI itself
        // is Task 22b). No first-class "project directory" concept exists yet — default
        // to the home directory until a folder-picker persists a real choice.
        let chosenWorkspace = persistence.load(SageWorkspaceSettings.self)
            .map { URL(fileURLWithPath: $0.workingDirectoryPath) }
        let assistantWorkingDirectory = chosenWorkspace ?? FileManager.default.homeDirectoryForCurrentUser
        let workspaceFileIndex = WorkspaceFileIndex(root: assistantWorkingDirectory)
        // Index ONLY a directory the user actually chose.
        //
        // The home directory is the fallback for the other consumers below
        // (repo instructions, project commands), where it costs a couple of
        // stats. For the file index it meant enumerating up to 20,000 files
        // under `~` — Downloads, Library, every checkout on the machine — at
        // every launch, to populate an `@`-mention list for a workspace the
        // user never picked. `refresh()` is now genuinely off-actor too (see
        // its doc comment: the old unqualified `Task` inherited main-actor
        // isolation, so the walk never left the main thread).
        if chosenWorkspace != nil {
            Task { await workspaceFileIndex.refresh() }
        }

        // Repo-instruction files (CLAUDE.md / AGENTS.md walked up from the active
        // workspace root) as a DISTINCT context source from the host's own
        // USER/MEMORY/AGENTS memory. mtime-cached inside the loader; the hub polls
        // it each turn, gated by `AgentContextSettingsStore` via its `kind`. Same
        // register-a-closure pattern as `MemoryContextSource`.
        let repoInstructionsLoader = RepoInstructionsLoader(root: assistantWorkingDirectory)
        _ = agentContextService.hub.register(appID: "host.repo-instructions") {
            repoInstructionsLoader.snapshot()
        }

        // Skill `/name` commands (Task 11): registered after the builtins, through
        // the same seam skill commands are documented to use — `register(_:)`
        // never lets a skill-bound name overwrite a builtin (`SkillCommandStore`
        // already refuses to persist a colliding binding, and
        // `slashCommands(registry:)` filters `BuiltinCommands.reservedNames` again
        // here as defense in depth).
        for command in skillCommandStore.slashCommands(registry: skillRegistry) {
            commandRegistry.register(command)
        }

        // File-based custom slash commands (project + user). Registered AFTER skill
        // commands so a colliding name can't shadow a skill binding; `CustomCommandStore`
        // already refuses builtin names, and re-registration drops stale names first.
        // Custom commands are hand-authored markdown — vault.
        let commandUserRoot = home.shared(.commands)
        let customCommandStore = CustomCommandStore(paths: CustomCommandPaths(
            userRoot: commandUserRoot,
            projectRoot: CustomCommandPaths.projectRoot(forWorkspace: assistantWorkingDirectory)))
        var liveCustomNames = resyncCustomCommands(
            store: customCommandStore, registry: commandRegistry, previous: [])
        let customCommandWatcher = CustomCommandWatcher(
            directory: commandUserRoot) {
                customCommandStore.reload()
                liveCustomNames = resyncCustomCommands(
                    store: customCommandStore, registry: commandRegistry, previous: liveCustomNames)
            }
        customCommandWatcher.start()

        // Tool Hooks (M8 assistant-tool-hooks) — the store is a live, persisted
        // CRUD surface (Task 6's settings view binds directly to this same
        // instance, returned below) and the runner consults it on every
        // PreToolUse/PostToolUse call. ONLY the main interactive session below
        // gets a runner: background (`BackgroundRunRunner` above) and subagent
        // (`makeSubagentSession` below) sessions stay hookless this milestone —
        // an unattended run auto-executing a user-authored shell hook is
        // deferred, not silently granted.
        let toolHooksStore = ToolHooksStore(persistence: persistence)
        let toolHookRunner = ToolHookRunner(
            store: toolHooksStore, router: executionRouter,
            workingDir: { assistantWorkingDirectory.path })

        let agentSession = AgentSession(
            providerFor: providerFor,
            connections: connectionStore,
            config: agentConfigStore,
            context: agentContextService,
            registry: agentToolRegistry,
            permissions: agentPermissionStore,
            memory: memoryService,
            agents: agentStore,
            editJournal: editJournal,
            toolStream: toolStreamStore,
            terminalController: terminalController,
            router: modelRouter,
            usage: usageTracker,
            runtime: runtimeOptionsStore,
            commands: commandRegistry,
            authProfiles: authProfileStore,
            candidatesProvider: candidatesProvider,
            isLocalConnection: { [localModelProbe] connection in localModelProbe.isLocal(connection) },
            mcpTrust: { [weak mcpServerRegistry] name in mcpServerRegistry?.isToolTrusted(name) ?? false },
            hooks: toolHookRunner
        )

        // Durable checkpoints (Checkpoint & Rewind, Task 8): the coordinator is built
        // AFTER `agentSession` exists because its `transcriptIndex` closure needs to
        // read back into the session (chicken/egg with passing it into the initializer
        // above). `persistence` is the shared app store, so checkpoints saved here
        // survive relaunch — `CheckpointCoordinator.init` loads them back from disk.
        let checkpointCoordinator = CheckpointCoordinator(
            sessionID: "main",
            // Checkpoint blobs are pre-mutation copies of files that still exist in
            // the user's workspace (and are git-recoverable) — derivable, so cache.
            snapshots: WorkspaceSnapshotStore(
                root: home.cacheRoot.appendingPathComponent("Checkpoints", isDirectory: true)),
            git: GitWorkingTreeSnapshotter(router: executionRouter),
            persistence: persistence,
            transcriptIndex: { [weak agentSession] in agentSession?.messages.count ?? 0 },
            defaultWorkingDir: assistantWorkingDirectory.path)
        agentSession.setCheckpointer(checkpointCoordinator)

        // Restore the last-active persisted session into the live session so a
        // returning user sees their previous conversation — and so the first edit
        // after launch doesn't overwrite the saved transcript with an empty one.
        if !assistantSessionStore.activeMessages.isEmpty {
            agentSession.replaceMessages(assistantSessionStore.activeMessages)
        }

        // Subscription OAuth: the main interactive session resolves a `.subscription`
        // connection's credential through the SAME shared resolver as the subagent and
        // background sessions (built above). `oauthStore` is returned so the settings
        // UI drives sign-in/sign-out through the instance the sessions read from.
        agentSession.credentialResolver = credentialResolver

        let voiceService = VoiceService(persistence: persistence, connections: connectionStore)
        voiceService.attachSession(agentSession)

        return (
            subagentCoordinator, runManager, assistantSessionStore, scheduleStore, scheduleRunner, triggerDispatcher,
            fileChangeWatcher, assistantWorkingDirectory, workspaceFileIndex, agentSession, voiceService, menuBarPresence,
            oauthStore, toolHooksStore, customCommandStore, customCommandWatcher,
            remoteChannelSettingsStore, remoteChannelService
        )
    }

    /// The production `makeSession` closure for `AgentSessionSubagentRunner` (M7 Slice 3
    /// Task 11 — the seam Task 6 deferred). Every child `AgentSession` this builds is:
    /// - **`unattended: true`** — a `.requireApproval` tool auto-denies instead of parking
    ///   on an approval HUD that a headless subagent can never answer (Task 8's gate).
    ///   This can only narrow what a child may do, never approve something the gate
    ///   itself would have blocked.
    /// - **model-PINNED, not re-routed** — the caller (`AgentSessionSubagentRunner.run`)
    ///   already resolved `model` via the Model Router within the spec's budget ceiling;
    ///   handing the child its own `router`/`candidatesProvider` would let it re-route on
    ///   every tool-loop turn and drift off that decision. Instead the resolved model is
    ///   pinned via a private, in-memory `RuntimeOptionsStore` — `resolveTurn`'s degraded
    ///   path (`pin ?? agents?.active.defaultModel ?? config.current.model`) then always
    ///   picks it.
    /// - scoped to the **filtered registry** the runner already narrowed via
    ///   `SubagentRegistryFilter`, with the profile's `instructions` as the base prompt.
    ///
    /// Extracted as a static, standalone-callable factory (rather than inlined in
    /// `bootstrap()`) so a wiring test can exercise it without spinning up the entire
    /// `AppEnvironment`.
    static func makeSubagentSession(
        providerFor: @escaping @MainActor (Connection) -> LLMProvider,
        connections: ConnectionStore,
        agentConfigStore: AgentConfigStore,
        agentContextService: AgentContextService,
        agentPermissionStore: AgentPermissionStore,
        agentStore: AgentStore,
        credentialResolver: @escaping (Connection) async throws -> [ProviderCredential]
    ) -> @MainActor (AgentProfile, AgentToolRegistry, String, Set<String>) -> AgentSession {
        { profile, registry, model, sandboxAllowList in
            let pinned = RuntimeOptionsStore(persistence: InMemoryPersistenceStore())
            pinned.pinModel(model)
            let session = AgentSession(
                providerFor: providerFor,
                connections: connections,
                config: agentConfigStore,
                context: agentContextService,
                registry: registry,
                permissions: agentPermissionStore,
                basePrompt: profile.instructions.isEmpty ? AgentSession.defaultPrompt : profile.instructions,
                agents: agentStore,
                // M7 Slice 3b Task 21: every child session is sandboxed at trust
                // tier `.subagent` — `sandboxAllowList` is always non-nil here (the
                // runner resolves it per-run via `ExecutionRouter.resolveProfile`),
                // so the compose layer is always active for a spawned subagent.
                // `agentAllowList: nil` — see Task 21 report: `AgentToolPolicy`'s
                // `.restricted` case (deny-list + tool-class allow) doesn't reduce
                // losslessly to `compose`'s `Set<String>?` allow-only shape, and the
                // full policy is already enforced by `SubagentRegistryFilter` (the
                // child's registry never even contains a disallowed tool) — a lossy
                // second projection here would risk incorrectly denying a call the
                // class-based allow already permits.
                unattended: true,
                sandboxAllowList: sandboxAllowList,
                agentAllowList: nil,
                runtime: pinned)
            session.credentialResolver = credentialResolver   // subscription works in subagents too
            return session
        }
    }
}
