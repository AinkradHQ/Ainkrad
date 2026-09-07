import Foundation
import AinkradAppKit
import AinkradHostRuntime

/// `AppEnvironment.bootstrap(home:defaults:)` split into cohesive helpers
/// (M7 finalize Wave D, D2) — this file holds the next two sequential
/// blocks: the sandbox/execution router + the host-facing agent tools, then
/// the Model Router / Usage / Failover wiring (M7 Slice 5b). Pure
/// value-construction, mirroring `bootstrap()`'s original order exactly.
extension AppEnvironment {
    /// Third block of `bootstrap()`: M7 Slice 6 (Security & Sandboxing) —
    /// every execution backend registered by kind, plus the base agent tool
    /// set (read/edit/workspace/terminal/git, memory tools if available,
    /// skill tools, MCP registry, and the Live Scry render tool).
    static func bootstrapExecutionAndTools(
        home: Home,
        persistence: PersistenceStore,
        secrets: SecretStore,
        lspServerRegistry: LSPServerRegistry,
        editJournal: EditJournal,
        workspaceManager: WorkspaceManager,
        agentActionHub: AgentActionRegistryHub,
        agentContextHub: AgentContextRegistryHub,
        memoryService: MemoryService?,
        mcpConfigStore: MCPServerConfigStore,
        // App-hosted MCP (M9): the app registry is EMPTY at this point — apps
        // are installed later, by `registry.install(...)` in
        // `finalizeBootstrap`. Both are held only inside closures that read
        // them at call time, never eagerly.
        appRegistry: BuiltInAppRegistry,
        pluginLaunchHub: PluginLaunchHub,
        skillRegistry: SkillRegistry,
        // Read per tool call so the foreground `run_terminal` can demote itself
        // off `HostBackend` when the session is unattended (Full-auto) — see
        // `RunTerminalTool.effectiveTier`. A closure rather than the store
        // itself: this block must not gain a dependency on the permission
        // subsystem's shape, only on the one value it needs.
        permissionMode: @escaping @MainActor () -> AgentPermissionMode
    ) -> (
        sandboxProfileStore: SandboxProfileStore,
        cloudCredentialsStore: CloudCredentialsStore,
        executionRouter: ExecutionRouter,
        agentTools: [any AgentTool],
        mcpServerRegistry: MCPServerRegistry,
        canvasStore: ScryStore,
        signalReadAccess: SignalReadAccess,
        toolStreamStore: ToolStreamStore,
        terminalController: TerminalProcessController
    ) {
        // M7 Slice 6: every backend is registered by its own kind — host
        // (trusted-main only, unchanged), seatbelt (macOS sandbox-exec),
        // docker + ssh (feature-detected: `isAvailable()` self-reports false
        // when the CLI/daemon/connection isn't present). Construction here
        // never spawns a process or blocks the launch/main-actor path —
        // `DockerBackend`/`SSHBackend`/`SeatbeltBackend` only stat a path or
        // check a stored `nil` connection at init; the actual (bounded,
        // async) availability probe happens lazily inside `router.route`,
        // per call. No backend is registered as a fallback for another kind —
        // an unregistered/unavailable backend fails closed in
        // `ExecutionRouter.route`, never substituting host.
        //
        // `.cloud` (Task 16): `ModalCloudBackend.isAvailable()` self-reports
        // false until a Modal token is stored via `cloudCredentialsStore` —
        // and even once configured, `AgentExecutionPolicy.allowCloud` (never
        // a tier default; see `ExecutionRouter.route`) is still required
        // before this backend is even attempted, and its `remoteExec` driver
        // is a fail-closed research stub (see `ModalCloudBackend`). Cloud
        // never becomes a working "just works" path from this wiring alone.
        // Terminal streaming (Task 7): one shared store + controller for the
        // MAIN foreground `RunTerminalTool`/`AgentSession` — live output rides
        // into the timeline via `toolStreamStore`; `terminalController` backs
        // `AgentSession.interrupt()`'s force-kill of the running child.
        let toolStreamStore = ToolStreamStore()
        let terminalController = TerminalProcessController()
        let sandboxProfileStore = SandboxProfileStore(persistence: persistence)
        let cloudCredentialsStore = CloudCredentialsStore(secrets: secrets)
        let executionRouter = ExecutionRouter(
            profiles: sandboxProfileStore,
            backends: [
                .host: HostBackend(),
                .seatbelt: SeatbeltBackend(),
                .docker: DockerBackend(),
                // Remote targets are resolved PER CALL from `run_terminal`'s
                // `remote` argument, through Leyline's host-only
                // `leyline.resolve_connection` action. No ambient "active
                // remote" exists, and with Leyline absent the resolver fails
                // and `SSHBackend` refuses to run — never locally.
                .ssh: SSHBackend(resolveConnection:
                    LeylineConnectionResolver.make(hub: agentActionHub)),
                .cloud: ModalCloudBackend(credentials: cloudCredentialsStore),
            ])

        var agentTools: [any AgentTool] = [
            ReadFileTool(),
            EditFileTool(editQuality: EditQuality(registry: lspServerRegistry), journal: editJournal),
            // The launch hub carries `openApp`: since MCP tool calls no longer
            // force an app open, this is the assistant's ONLY way to honour
            // "open Lore".
            WorkspaceControlTool(workspaces: workspaceManager, launchHub: pluginLaunchHub),
            { var t = RunTerminalTool(actionHub: agentActionHub, router: executionRouter)
              t.toolStream = toolStreamStore; t.processController = terminalController
              t.permissionMode = permissionMode; return t }(),
            // Git and Pull-Request operations are no longer host tools: Git Mage
            // publishes them as `mcp/gitmage/*` over its in-process MCP server
            // (see `AppMCPDiscovery`), so they arrive through `dynamicTools`
            // below rather than being hard-coded here.
            TodoWriteTool(),
            PresentPlanTool(),
        ]
        // Registered unconditionally, unlike the memory tools above, because
        // the feed's existence is not known yet — the center is created in
        // `finalizeBootstrap`, after this array is consumed. The access handle
        // resolves at call time and reports unavailability as a result rather
        // than an error.
        let signalReadAccess = SignalReadAccess()
        agentTools.append(SignalSearchTool(access: signalReadAccess))
        // M8 web tools (read-class, gated like reads). web_fetch uses a
        // redirect-validating client so a 302 to a private host is never
        // dispatched; web_search hits a fixed Brave endpoint (key in SecretStore).
        agentTools.append(WebFetchTool(http: RedirectValidatingHTTPClient()))
        agentTools.append(WebSearchTool(backend: RoutingWebSearchBackend(
            persistence: persistence,
            brave: BraveSearchBackend(secrets: secrets, http: URLSessionDataHTTPClient()),
            duckduckgo: DuckDuckGoSearchBackend(http: URLSessionDataHTTPClient()),
            searxngHTTP: URLSessionDataHTTPClient())))
        if let memoryService {
            _ = agentContextHub.register(appID: "host.memory") {
                MemoryContextSource.snapshot(from: memoryService)
            }
            agentTools.append(MemoryWriteTool(service: memoryService))
            agentTools.append(MemorySearchTool(service: memoryService))
        }
        // MCP (M7 Slice 2): configured servers + their live connections. Uses
        // `MCPServerRegistry.defaultClientFactory` (the real stdio/httpSSE transport
        // factory, the one place real transports get instantiated) — tests inject a
        // stub factory instead so the registry core never spawns a process or hits
        // the network. Connecting is kicked off after `environment` exists (below),
        // never awaited here, so a down/misconfigured server can't delay launch.
        //
        // App-hosted MCP servers (M9): one server per installed app that opts
        // into `AinkradAppMCP`. Every collaborator is a closure resolved at
        // CALL time, because none of this data exists yet — the app registry is
        // still empty here and `pluginLaunchHub`'s open/availability handlers
        // are installed in `finalizeBootstrap`. The activator memoizes each
        // server on first use, so a server is built once and holds its app's
        // live state. The matching `AppMCPDiscovery.refresh` call lives in
        // `finalizeBootstrap`, right after the apps are actually installed.
        // Late-bound on purpose: the flag lives on the MCP registry's discovered
        // descriptors, and that registry is built FROM this activator two
        // statements below. Boxing the reference is the same trick the closures
        // above use for `pluginLaunchHub` — resolve at call time, not here.
        var mcpRegistryForLiveAppFlag: (() -> MCPServerRegistry?)?
        let appServerActivator = AppServerActivator(
            serverFor: { [weak appRegistry] appID in
                appRegistry?.allApps.first { $0.id == appID }?.mcpServerFactory?()
            },
            // Both open-state and launch go through the hub: "open" must count
            // an `.overlay`-presented app, which has no `tileLayout` block —
            // asking `workspaceManager` alone would report a live overlay app
            // as closed and every dispatch to it would wait out the launch
            // timeout. `AppEnvironment.isAppOpen` composes the two halves; the
            // hub is how that late-created answer reaches this closure.
            isAppOpen: { [weak pluginLaunchHub] appID in
                pluginLaunchHub?.isOpen(appID) ?? false
            },
            requestOpen: { [weak pluginLaunchHub] appID in pluginLaunchHub?.requestOpen(appID) },
            availability: { [weak pluginLaunchHub] appID in
                pluginLaunchHub?.availability(of: appID) ?? .unknown
            },
            // No registry yet (or no discovery done) means no app has claimed it
            // needs its window, so the call runs in the background — which is
            // what a tool call should do.
            requiresLiveApp: { appID, method, name in
                mcpRegistryForLiveAppFlag?()?
                    .requiresLiveApp(appID: appID, method: method, name: name) ?? false
            })
        // The other half of that memoization: a torn-down app's cached server
        // must not outlive the instance it was built over. `deregister` is the
        // one place an app is finished with (it already calls the app's own
        // `teardown`), so the host-side eviction hangs off the same seam.
        appRegistry.onAppTornDown = { [weak appServerActivator] appID in
            appServerActivator?.evict(appID: appID)
        }
        let mcpServerRegistry = MCPServerRegistry(configStore: mcpConfigStore,
                                                  activator: appServerActivator)
        // Closes the loop opened above. Weak so the activator's closure cannot
        // keep the registry alive past teardown.
        mcpRegistryForLiveAppFlag = { [weak mcpServerRegistry] in mcpServerRegistry }
        // Read-class complement to the tool-call path above: fetches one
        // resource's full contents on demand (see `MCPReadResourceTool` doc
        // comment for why this exists alongside `<workspace_context>`).
        agentTools.append(MCPReadResourceTool(registry: mcpServerRegistry))

        // Skill-index context source (Task 5) + agent-facing tools (Task 6/7).
        // Both hold the mutable `skillRegistry` reference and read its live set at
        // execute-time, so a reload (install/approve/discard) is reflected without
        // re-registering anything here.
        _ = agentContextHub.register(appID: "host.skills") {
            SkillIndexContextSource.snapshot(from: skillRegistry)
        }
        agentTools.append(UseSkillTool(registry: skillRegistry))
        agentTools.append(ProposeSkillTool(registry: skillRegistry))

        // M7 Slice 7 (Live Scry): `scry_render` only draws structured cards
        // from agent-supplied data — it executes nothing and touches no files
        // or system state (see `ScryRenderTool`), so it's appended alongside
        // the other read-class tools. `canvasStore` defaults to sessionKey
        // "default" (PROVISIONAL — per-session keying awaits a stable session
        // identifier from Slice 5; see Task 12 brief).
        let canvasStore = ScryStore(persistence: persistence)
        agentTools.append(ScryRenderTool(store: canvasStore))

        // Media tools (read-class, render to the Live Scry). Key in SecretStore.
        agentTools.append(ImageGenerateTool(
            backend: RoutingMediaBackend(
                persistence: persistence,
                secrets: secrets,
                openai: OpenAIImageBackend(secrets: secrets, http: URLSessionDataHTTPClient()),
                pollinations: PollinationsImageBackend(http: URLSessionDataHTTPClient()),
                stability: StabilityImageBackend(secrets: secrets, http: URLSessionDataHTTPClient()),
                replicate: ReplicateImageBackend(secrets: secrets, http: URLSessionDataHTTPClient()),
                google: GoogleImagenBackend(secrets: secrets, http: URLSessionDataHTTPClient()),
                huggingface: HuggingFaceImageBackend(secrets: secrets, http: URLSessionDataHTTPClient()),
                auxHTTP: URLSessionDataHTTPClient()),
            store: canvasStore))
        // Generated media (image/video/speech output) is irreplaceable —
        // re-running a prompt yields different output — so it lives in the
        // vault, not the cache. Shared across the video and speech tools.
        let generatedMediaStore = GeneratedMediaStore(baseDirectory: home.shared(.media))
        agentTools.append(VideoGenerateTool(
            backend: RoutingVideoBackend(
                persistence: persistence,
                secrets: secrets,
                replicate: ReplicateVideoBackend(secrets: secrets, http: URLSessionDataHTTPClient()),
                luma: LumaVideoBackend(secrets: secrets, http: URLSessionDataHTTPClient()),
                fal: FalVideoBackend(secrets: secrets, http: URLSessionDataHTTPClient()),
                auxHTTP: URLSessionDataHTTPClient()),
            store: canvasStore, mediaStore: generatedMediaStore))
        agentTools.append(SpeakTool(
            synth: RoutingSpeechSynthesizer(
                persistence: persistence, secrets: secrets, onDevice: SystemSpeechSynthesizer(),
                http: URLSessionDataHTTPClient(), player: SystemAudioPlayer()),
            producer: RoutingSpeechAudioProducer(
                persistence: persistence, secrets: secrets, http: URLSessionDataHTTPClient(),
                onDevice: OnDeviceSpeechAudioProducer()),
            store: canvasStore, mediaStore: generatedMediaStore))

        // M8 code-search tools (read-class). Share the assistant workspace root,
        // resolved live so a folder change is reflected without re-registering —
        // same derivation as the @-mention index in bootstrapSession.
        let searchRootProvider: @MainActor () -> URL = { [persistence] in
            persistence.load(SageWorkspaceSettings.self)
                .map { URL(fileURLWithPath: $0.workingDirectoryPath) }
                ?? FileManager.default.homeDirectoryForCurrentUser
        }
        agentTools.append(GrepTool(rootProvider: searchRootProvider))
        agentTools.append(GlobTool(rootProvider: searchRootProvider))

        return (sandboxProfileStore, cloudCredentialsStore, executionRouter, agentTools, mcpServerRegistry, canvasStore,
                signalReadAccess, toolStreamStore, terminalController)
    }

    /// Fourth block of `bootstrap()`: Model Router / Usage / Failover
    /// wiring (M7 Slice 5b) — the model catalog, price table, usage tracker,
    /// router, local-model reachability probe/cache, auth profiles, the
    /// router `candidatesProvider` closure, and the command registry
    /// (builtins + `/stop`).
    static func bootstrapModelRouting(
        persistence: PersistenceStore,
        // `agents.json` is an Sage/ document, not a Config/ one — see
        // `bootstrapCoreStores`. Everything else in this block is Config/.
        assistantDocuments: PersistenceStore,
        secrets: SecretStore,
        connectionStore: ConnectionStore,
        discoveredModelsStore: DiscoveredModelsStore
    ) -> (
        modelCatalogService: ModelCatalogService,
        agentStore: AgentStore,
        modelCatalog: ModelCatalog,
        modelPriceTable: ModelPriceTable,
        routerOutcomeStore: RouterOutcomeStore,
        modelRouter: ModelRouter,
        usageTracker: UsageTracker,
        runtimeOptionsStore: RuntimeOptionsStore,
        localModelProbe: LocalModelProbe,
        localModelAvailability: LocalModelAvailability,
        authProfileStore: AuthProfileStore,
        candidatesProvider: @MainActor () -> [RouterCandidate],
        commandRegistry: CommandRegistry
    ) {
        let modelCatalogService = ModelCatalogService(http: URLSessionDataHTTPClient())
        let agentStore = AgentStore(persistence: assistantDocuments)

        // Model Router / Usage / Failover wiring (M7 Slice 5b). Every one of these is
        // degrade-don't-crash: `AgentSession` treats them as optional and falls back to
        // pre-Slice-5b behavior (config.current model, single connection, no command
        // interception) if any were nil, mirroring the Slice 1 pattern.
        let modelCatalog = ModelCatalog()
        let modelPriceTable = ModelPriceTable()
        let routerOutcomeStore = RouterOutcomeStore(persistence: persistence)
        let modelRouter = ModelRouter(catalog: modelCatalog, outcomes: routerOutcomeStore)
        let usageTracker = UsageTracker(persistence: persistence, prices: modelPriceTable)
        let runtimeOptionsStore = RuntimeOptionsStore(persistence: persistence)
        let localModelProbe = LocalModelProbe(catalog: modelCatalogService)
        // Async-refreshed reachability cache — see `LocalModelAvailability`. Kicked off
        // (initial + periodic) below, once `connectionStore`/`localModelProbe` exist.
        let localModelAvailability = LocalModelAvailability()
        let authProfileStore = AuthProfileStore(persistence: persistence, secrets: secrets)

        // Candidates = every configured connection's curated model list, resolved
        // against the bundled `ModelCatalog` for tier/capability metadata (falling back
        // to a conservative cheap-paid/tool-use-only descriptor for a model the catalog
        // doesn't recognize yet). Synchronous by design (`candidatesProvider` is called
        // once per turn from `resolveTurn`) — live discovery (`localModelProbe`,
        // `modelCatalogService`) is async and is not woven directly into the fetch, but
        // its OUTPUT (`localModelAvailability.reachableConnectionIDs`, refreshed
        // out-of-band) IS consulted synchronously here to drop LOCAL candidates whose
        // server isn't currently reachable — otherwise a down Ollama/LM Studio gets
        // picked free-first and every turn fails with "Could not connect to the server."
        let candidatesProvider: @MainActor () -> [RouterCandidate] = { [connectionStore, modelCatalog, localModelProbe, localModelAvailability, discoveredModelsStore] in
            let all = connectionStore.connections.flatMap { connection -> [RouterCandidate] in
                // Prefer the connection's LIVE-discovered models; fall back to the
                // preset's curated list only when nothing was ever discovered. This
                // is what lets the Auto router pick a real provider model rather than
                // a hardcoded curated one.
                let models = discoveredModelsStore.models(for: connection.id)
                    ?? ProviderPreset.preset(id: connection.presetID).curatedModels
                return models.map { modelID in
                    RouterCandidate(
                        connectionID: connection.id, model: modelID,
                        descriptor: modelCatalog.descriptor(for: modelID)
                            ?? ModelDescriptor(id: modelID, tier: .cheapPaid, contextWindow: 128_000, capabilities: [.toolUse]))
                }
            }
            return RouterOrdering.filterReachableCandidates(
                all,
                reachableLocalConnectionIDs: localModelAvailability.reachableConnectionIDs,
                isLocalConnection: { id in
                    connectionStore.connections.first(where: { $0.id == id }).map(localModelProbe.isLocal) ?? false
                }
            )
        }

        let commandRegistry = CommandRegistry(builtins: BuiltinCommands.make(
            runtime: runtimeOptionsStore, usage: usageTracker, router: modelRouter, catalog: modelCatalog))
        // M7 Slice 3 (Autonomy) Task 11: `/stop` interrupts the in-flight turn.
        // `/undo` and `/retry` are already registered as builtins (Task 10).
        commandRegistry.register(SlashCommand(
            name: "stop", summary: "Interrupt the current turn", usage: "/stop", category: .session) { _, session in
            session.interrupt()
            return .handled(note: "Interrupted.")
        })

        return (
            modelCatalogService, agentStore, modelCatalog, modelPriceTable, routerOutcomeStore, modelRouter,
            usageTracker, runtimeOptionsStore, localModelProbe, localModelAvailability, authProfileStore,
            candidatesProvider, commandRegistry
        )
    }
}
