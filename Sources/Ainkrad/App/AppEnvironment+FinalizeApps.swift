import AinkradAppKit
import AinkradHostRuntime
import Foundation
import SwiftUI

/// Finalize phase 2 of 2 (see `finalizeBootstrap`): launch-time I/O, the built-in
/// apps (Rune settings migration, Sage, Scry, Hoard with its MCP server and context),
/// plugin loading, app-hosted MCP, connect-enabled, layout restore and the open handlers.
extension AppEnvironment {
    static func finalizeApps(
        environment: AppEnvironment,
        signalCenter: SignalCenter,
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
        pluginLaunchHub: PluginLaunchHub,
        appAppearanceStore: AppAppearanceStore,
        pluginDataRoot: URL,
        pluginDirs: [URL],
        loader: PluginLoader,
        registry: BuiltInAppRegistry,
        workspaceManager: WorkspaceManager,
        defaults: UserDefaults
    ) {
        recordFinalizePhase("apps")
        // Launch-time external I/O (local-model probes, MCP connect, LSP
        // autodetect) is skipped when the app is hosting a test bundle: under
        // `xcodebuild test` these otherwise hang the shared process on network
        // timeouts / a TCC prompt, starving the tests. See
        // `LaunchHomeResolver.isRunningTests`. Guarded as one block since all
        // three are the same "background external I/O off the launch path" class.
        if !LaunchHomeResolver.isRunningTests {
            // Kick the local-reachability cache: an immediate refresh so the very
            // first turn already reflects reality (best-effort — a turn started
            // before this completes just sees the cache's initial empty state,
            // which is safe: local candidates are dropped, not hung on), then a
            // 30s repeating loop so a server started/stopped mid-session is
            // picked up without requiring a model-picker visit. Runs for the
            // process lifetime of `environment`, mirroring other bootstrap-owned
            // background loops in this app (e.g. sound/theme observers).
            Task { [weak connectionStore, weak localModelProbe] in
                while !Task.isCancelled {
                    guard let connectionStore, let localModelProbe else { return }
                    await localModelAvailability.refresh(
                        connections: connectionStore.connections, probe: localModelProbe,
                        tokenFor: { connectionStore.token(for: $0) })
                    // Jitter: `Task.sleep` has no tolerance, so spread the wakeup
                    // over a 5s window rather than waking every client on the
                    // same 30s boundary.
                    try? await Task.sleep(for: .seconds(30 + Double.random(in: 0...5)))
                }
            }

            // Seed autodetected LSP servers off the launch path: `autodetect()` shells out to
            // `which` once per known server (a handful of `Process` spawns), so it runs inside
            // this unawaited `Task` rather than synchronously in `bootstrap()`. `seedIfEmpty`
            // is a no-op once the user has any configs (from a prior autodetect or a manual
            // edit in the LSP config UI), so this only ever does something on first launch.
            Task { [weak lspServerRegistry] in
                let configs = LSPServerRegistry.autodetect()
                await lspServerRegistry?.seedIfEmpty(with: configs)
            }
        }

        // Rune (formerly Terminal) ships as an App Store plugin, not compiled in.
        // Still migrate any pre-4a host-global settings into its scoped store so the
        // installed plugin sees the user's existing configuration. Scoped to "rune":
        // `AppDataDirectoryRename` has already moved <Apps>/terminal to <Apps>/rune
        // earlier in bootstrap, so writing to the old id would strand this migration
        // in a directory the plugin no longer reads.
        let runeHost = HostServicesImpl(
            appID: "rune", dataRootURL: pluginDataRoot,
            secretStore: secrets, themeManager: themeManager,
            hub: agentContextHub, actionHub: agentActionHub, launchHub: pluginLaunchHub, signalHub: signalHub,
            declaredPresentation: .pane, appAppearanceStore: appAppearanceStore)
        TerminalSettingsMigration.runIfNeeded(
            legacyRawPayload: { (persistence as? FileDocumentStore)?.rawPayloadData(forID: $0) },
            scoped: runeHost.documents, defaults: defaults)

        // Sage is a host-embedded built-in (its views read `AppEnvironment`
        // directly), scoped like any other app for its documents/secrets/theme/context.
        let sageHost = HostServicesImpl(
            appID: "sage", dataRootURL: pluginDataRoot,
            secretStore: secrets, themeManager: themeManager,
            hub: agentContextHub, actionHub: agentActionHub, launchHub: pluginLaunchHub, signalHub: signalHub,
            declaredPresentation: .pane, appAppearanceStore: appAppearanceStore)

        // Live Scry (M7 Slice 7) is likewise a host-embedded built-in — its
        // pane reads `AppEnvironment.scryStore` directly (see `ScryApp`).
        let scryHost = HostServicesImpl(
            appID: "scry", dataRootURL: pluginDataRoot,
            secretStore: secrets, themeManager: themeManager,
            hub: agentContextHub, actionHub: agentActionHub, launchHub: pluginLaunchHub, signalHub: signalHub,
            declaredPresentation: .pane, appAppearanceStore: appAppearanceStore)

        // Hoard (M1) — a host-embedded built-in like Sage and Scry. It
        // inherits the host's unsandboxed filesystem access; its own views read
        // `AppEnvironment` directly.
        let hoardHost = HostServicesImpl(
            appID: "hoard", dataRootURL: pluginDataRoot,
            secretStore: secrets, themeManager: themeManager,
            hub: agentContextHub, actionHub: agentActionHub, launchHub: pluginLaunchHub, signalHub: signalHub,
            declaredPresentation: .pane, declaredMode: .basic,
            appAppearanceStore: appAppearanceStore)

        // Hoard' MCP server and agent context are built HERE, not in
        // `HoardApp`, for the same reason its settings are: the SDK entry
        // points are static and see only `HostServices`, while the server must
        // drive the live stores on `AppEnvironment`. Hoard is host-embedded, so
        // the host is entitled to wire it directly.
        var filesRegistration = RegisteredApp.builtIn(
            HoardApp.self,
            summary:
                "Browse, search and organise your files — keyboard-driven, git-aware, and wired into the assistant.",
            host: hoardHost,
            chromeFillOverride: {
                HoardApp.surfaceFill(
                    opacity: appAppearanceStore.surfaceOpacity("hoard"),
                    base: themeManager.tokens.background
                )
            },
            // A built-in declares its default here, where a plugin declares it
            // in its Info.plist. Hoard opens basic: reaching a file is what it
            // is opened for, and the sidebar, tabs and preview are for
            // organising rather than reaching.
            mode: .basic)
        filesRegistration.mcpServerFactory = { [weak environment] in
            guard let environment else { return MCPAppServer(appID: HoardApp.id) }
            return HoardMCPServer.make(environment: environment)
        }

        // Publish what the user is looking at, so the assistant has the
        // browser's state without having to ask for it.
        _ = hoardHost.context.register { [weak environment] in
            guard let environment,
                let summary = environment.filesPaneCoordinator.contextSummary
            else { return nil }
            return AgentContextSnapshot(
                kind: "hoard", title: "Hoard", text: summary)
        }

        let loaded = loader.loadAll(from: pluginDirs)
        // A bundle that fails to load is the most confusing failure in the
        // product: the app is simply absent, with nothing on screen saying why.
        // It was already recorded in `registry.loadFailures` and read by the
        // App Store overlay only — so a user who never opens that overlay had
        // no way to find out.
        for failure in loaded.failures {
            signalCenter.emit(.pluginLoadFailed(failure), from: .host)
        }
        registry.install(
            builtIn: [
                RegisteredApp.builtIn(
                    SageApp.self,
                    summary:
                        "Your in-workspace AI assistant — chat about your code, run gated tools, and drive the terminal and git without leaving Ainkrad.",
                    host: sageHost,
                    // Reading `surfaceOpacity` inside this closure — invoked
                    // synchronously from `TileLayoutView.hasTranslucentPane`
                    // and `BlockView.headerBackground` during their view
                    // bodies — registers an @Observable dependency, so dialing
                    // the slider live re-evaluates the backdrop + header.
                    chromeFillOverride: {
                        SageApp.surfaceFill(
                            opacity: appAppearanceStore.surfaceOpacity("sage"),
                            base: themeManager.tokens.background
                        )
                    },
                    // Advanced by default: the transcript history and the runs
                    // panel are why Sage is opened as a pane at all. Basic is
                    // the deliberate switch, and Quick Ask already covers the
                    // one-off case from the keyboard.
                    mode: .advanced
                ),
                RegisteredApp.builtIn(
                    ScryApp.self,
                    summary:
                        "The Live Scry — the assistant lays out tables, diagrams, charts, code and status as movable HUD cards.",
                    host: scryHost),
                filesRegistration,
            ],
            loaded: loaded.apps,
            failures: loaded.failures
        )

        // App-hosted MCP servers (M9): `registry.install` above is the FIRST
        // moment any `RegisteredApp` — and therefore any `mcpServerFactory` —
        // exists, so discovery has to run here rather than beside the
        // `MCPServerRegistry` construction in `bootstrapExecutionAndTools`
        // (where the registry object exists but holds no apps yet). This call
        // itself is purely static and synchronous — it reads a nullable closure
        // per app, opens nothing and awaits nothing. (The `connectEnabled()`
        // below is the part with real cost, and it is deliberately off the
        // launch path; it does NOT open apps, because `AppServerActivator`
        // force-opens only for `tools/call`/`resources/read`.)
        AppMCPDiscovery.refresh(apps: registry.allApps, into: mcpServerRegistry.configStore)

        // Connect enabled MCP servers off the launch path: `connectEnabled()` is async
        // and per-server bounded/degrade-don't-crash (see `MCPServerRegistry`), but
        // launch itself must never block on a slow or down server, so this is fired
        // from an unawaited `Task` rather than run synchronously in `bootstrap()`.
        // Tools/trust populate as servers come up; a down server just never appears.
        // MUST stay below `AppMCPDiscovery.refresh` above: it connects whatever configs
        // exist at that moment, so app-server configs have to be synthesized first.
        // Skipped under a hosted test run for the same reason as the block above.
        if !LaunchHomeResolver.isRunningTests {
            Task { [weak mcpServerRegistry] in
                await mcpServerRegistry?.connectEnabled()
            }
        }

        if let saved = persistence.load(LayoutStateSnapshot.self) {
            // Launch never resumes the last session: `launchState` drops the
            // workspaces the user never named, lands on main rather than
            // wherever they left off, and keeps pane contents only when
            // Settings → General → "Restore layout on launch" is on (default
            // off) — so opening the app starts no app on the user's behalf.
            let restorePanes = environment.generalSettingsStore.restoreLayoutOnLaunch
            let launch = saved.launchState(restoringPanes: restorePanes)
            workspaceManager.restore(from: launch)
            workspaceManager.pruneApps(keeping: Set(registry.allApps.map { $0.id }))
            let paneState = restorePanes ? "restored" : "cleared"
            Log.app.info(
                "Restored workspace layout: \(launch.workspaces.count) of \(saved.workspaces.count) workspace(s) kept, panes \(paneState, privacy: .public), active = main"
            )
        }
        workspaceManager.onStateChange = { [weak workspaceManager] in
            guard let workspaceManager else { return }
            persistence.save(workspaceManager.snapshot())
        }

        environment.launcherStore.presentOverlay = { [weak environment] appID in
            environment?.presentedOverlayAppID = appID
        }

        // Captures `[weak environment]` (rather than `[weak workspaceManager]`,
        // as pre-Slice-3) so it can also clear `presentedOverlayAppID` — any
        // app opening (tiled or via this hub) dismisses a summoned plugin
        // overlay, mirroring the Settings/App Store overlays' dismiss-on-open.
        pluginLaunchHub.setOpenHandler { [weak environment] appID in
            guard let environment else { return }
            let declared = environment.registry.allApps.first { $0.id == appID }?.presentation ?? .pane
            let effective = environment.appAppearanceStore.presentationOverride(appID) ?? declared
            if effective == .overlay {
                environment.presentedOverlayAppID = appID
            } else {
                let layout = environment.workspaceManager.activeWorkspace.tileLayout
                let intent = AinkradLaunchIntent.decode(environment.pluginLaunchHub.peekPending(for: appID))
                // A document for an app already open here goes to THAT pane:
                // focus it and remount its root so it collects the payload.
                // Documents only — any other launch (an SSH session for Rune)
                // wants a pane of its own, and a remount would end its session.
                if let existing = layout.paneForDocument(appID: appID, intent: intent) {
                    layout.focus(existing.id)
                    existing.launchGeneration += 1
                    environment.presentedOverlayAppID = nil
                    return
                }
                let block = layout.openApp(appID)
                // Honour the mode the LAUNCH asked for, when it asked for one.
                //
                // Without this the intent's `mode` was carried and then ignored:
                // Hoard enqueued a document for Lore in `.basic`, the pane
                // opened in Lore's configured mode (advanced), and only the
                // BASIC root consumes a pending launch — so the payload sat
                // unread and the file never opened. Peeked, not taken: the app
                // itself still consumes it.
                if let requested =
                    AinkradLaunchIntent
                    .decode(environment.pluginLaunchHub.peekPending(for: appID))?.mode
                {
                    block.mode = requested
                }
                environment.presentedOverlayAppID = nil
            }
        }

        // Counterpart to the open handler, for callers that need a live shell
        // rather than a launch — currently the app-hosted MCP activator, which
        // must not re-launch (and then time out waiting for) an app that is
        // already up. Installed here, with the same `[weak environment]` late
        // binding as the two handlers around it, because `presentedOverlayAppID`
        // only exists once `environment` does.
        pluginLaunchHub.setOpenStateProvider { [weak environment] appID in
            environment?.isAppOpen(appID) ?? false
        }

        // Generation 8: lets `apps.openReportingOutcome` tell a plugin WHY a
        // launch didn't happen. Leyline's "connect" used to look identical
        // whether Terminal opened or was never installed.
        pluginLaunchHub.setAvailabilityProvider { [weak environment] appID in
            guard let environment else { return .available }
            guard environment.registry.allApps.contains(where: { $0.id == appID }) else { return .unknown }
            return environment.registry.isEnabled(appID) ? .available : .disabled
        }

        Log.app.info("AppEnvironment bootstrapped with \(registry.allApps.count) registered app(s)")

        #if DEBUG
        if let (openAppID, payload) = parseDebugOpenAppArguments({ UserDefaults.standard.string(forKey: $0) }) {
            let registered = registry.allApps.first { $0.id == openAppID }
            if let registered, registry.isEnabled(openAppID) {
                if let payload {
                    pluginLaunchHub.enqueue(target: openAppID, payload: payload)
                }
                pluginLaunchHub.requestOpen(openAppID)
                Log.app.info("DEBUG launch arg: opened app \(openAppID, privacy: .public)")
            } else if registered == nil {
                Log.app.info("DEBUG launch arg: unknown app \(openAppID, privacy: .public)")
            } else {
                Log.app.info("DEBUG launch arg: disabled app \(openAppID, privacy: .public)")
            }
        }
        if parseDebugOpenGalleryArgument({ UserDefaults.standard.string(forKey: $0) }) {
            environment.isComponentGalleryPresented = true
            Log.app.info("DEBUG launch arg: presented Component Gallery")
        }
        #endif
    }
}
