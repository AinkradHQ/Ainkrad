import Foundation
import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

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
        // MARK: Signal (notification feed)
        //
        // Built here rather than in `bootstrapCoreStores` because it needs the
        // sound engine, the window state, and `environment` itself for the
        // popover's content closure — mirrors how `launcherStore.presentOverlay`/
        // `pluginLaunchHub` below capture `[weak environment]` rather than
        // being wired inside the initializer.
        let signalPreferencesStore = SignalPreferencesStore(
            url: home.cacheRoot.deletingLastPathComponent()
                .appendingPathComponent("signal-preferences.json"))
        let signalContextProvider = HostDeliveryContextProvider()
        let loadedSignalPreferences = signalPreferencesStore.load()
        // Its OWN engine, on its own settings. Sharing `environment.sounds`
        // meant General → Sound's chrome master silenced failure alerts, and
        // the Notifications pane never said so.
        let notificationSoundStore = NotificationSoundStore(
            settings: loadedSignalPreferences.sound)
        // WHETHER a notification cue plays is this store's business; WHICH
        // asset it plays is chosen in Settings → Sound, which writes to the
        // general store. Reading it here is what makes that choice take effect
        // — without it the per-event picker moved, previewed correctly, and
        // changed nothing about the sound an actual notification made.
        notificationSoundStore.effectSource = { [weak environment] event in
            environment?.generalSettingsStore.effect(for: event) ?? event
        }
        let notificationSounds = SoundEngine(settings: notificationSoundStore,
                                             overrideDirectory: home.shared(.sounds))
        let signalCenter = AppEnvironment.makeSignalCenter(
            storeURL: AppEnvironment.signalStoreURL(
                applicationSupport: home.cacheRoot.deletingLastPathComponent()),
            preferences: loadedSignalPreferences,
            sound: notificationSounds,
            toast: environment.signalToasts,
            contextProvider: signalContextProvider,
            badge: { _ in
                // Per-app badges are M2's `SignalBadgeModel`; the menu-bar
                // badge is driven by `onUnreadChanged` below, which covers
                // every path that changes the count rather than only delivery.
            })
        // "Visible" means the app has a surface the user can actually see, so
        // routing can tell "you are looking at Raven" from "Raven is installed".
        // `isAppOpen` is the host's own answer to that question and covers both
        // tiled panes and overlay presentation.
        signalContextProvider.visibleAppIDs = { [weak environment] in
            guard let environment else { return [] }
            return Set(environment.registry.enabledApps.map(\.id)
                .filter { environment.isAppOpen($0) })
        }
        // One writer for all three fields: a callback that rebuilt
        // SignalPreferences from two of them would drop whichever it forgot.
        let saveSignalPreferences = { [weak signalCenter, weak notificationSoundStore] in
            guard let signalCenter else { return }
            signalPreferencesStore.save(SignalPreferences(
                rules: signalCenter.rules,
                retention: signalCenter.retention,
                sound: notificationSoundStore?.settings ?? NotificationSoundSettings()))
        }
        signalCenter.onRulesChanged = { _ in saveSignalPreferences() }
        signalCenter.onRetentionChanged = { _ in saveSignalPreferences() }
        notificationSoundStore.onChange = { _ in saveSignalPreferences() }
        // Tapping a feed row opens the app that published it, with the event's
        // payload — the same cross-app launch path `HostServices.apps` uses, so
        // a deep link behaves exactly like an app opening another app.
        //
        // Factored into one closure because there are now two ways in: a deep
        // link, which names a destination and carries a payload, and a bare
        // reveal for the far more common notification that names no
        // destination at all. Everything after "which app" is identical, and
        // two copies of this would drift.
        let reveal: (String, String?, Data?) -> Void = { [weak environment] appID, locator, payload in
            guard let environment else { return }
            let declared = environment.registry.allApps
                .first { $0.id == appID }?.presentation ?? .pane
            let effective = environment.appAppearanceStore
                .presentationOverride(appID) ?? declared
            let action = SignalReveal.action(
                appID: appID,
                presentsAsOverlay: effective == .overlay,
                workspaces: environment.workspaceManager.workspaces.map { workspace in
                    SignalRevealWorkspace(
                        id: workspace.id,
                        panes: workspace.tileLayout.blocks.map {
                            SignalRevealWorkspace.Pane(
                                appID: $0.appID, blockID: $0.id,
                                locator: environment.paneLocators.locator(forBlock: $0.id))
                        })
                },
                activeWorkspaceID: environment.workspaceManager.activeWorkspaceID,
                // Generation 10: the app's own name for what the notification
                // is about. With three Rune panes open this is what makes the
                // click land on the session that called, instead of the first
                // pane of that app.
                locator: locator)

            // Enqueue only where something will actually collect it. The hub
            // holds ONE pending payload per app, so enqueuing on the `.focus`
            // path — where no pane is created and nothing pulls — left the
            // payload to be picked up by the next unrelated pane and clobbered
            // any legitimate pending launch on the way. See
            // `SignalRevealAction.deliversPayload`.
            //
            // A payload-less reveal must not enqueue AT ALL, for the same
            // reason: an empty payload is still a payload as far as the hub is
            // concerned, and it would evict a real one.
            if let payload, action.deliversPayload {
                pluginLaunchHub.enqueue(target: appID,
                                        payload: String(decoding: payload, as: UTF8.self))
            }

            switch action {
            case .presentOverlay:
                environment.presentedOverlayAppID = appID
            case .focus(let workspaceID, let blockID):
                // Focus what is already there. Going through `requestOpen`
                // appended a SECOND pane, so following a notification took the
                // user further from the session that called them.
                if workspaceID != environment.workspaceManager.activeWorkspaceID {
                    environment.workspaceManager.switchTo(workspaceID)
                }
                environment.workspaceManager.activeWorkspace.tileLayout.focus(blockID)
            case .openNewPane:
                pluginLaunchHub.requestOpen(appID)
            }
        }
        signalCenter.onActivateDeepLink = { link in
            reveal(link.appID, link.locator, link.payload)
        }
        // The fallback for the majority of notifications, which name no
        // destination: go to the app that published it, carrying nothing.
        signalCenter.onRevealSource = { appID in reveal(appID, nil, nil) }
        environment.signalCenter = signalCenter
        environment.notificationSounds = notificationSoundStore
        // Beside the preferences, not inside them: this is where the user was
        // LOOKING, not what they decided. Losing it is a minor annoyance, and
        // it must never be able to corrupt a routing rule.
        environment.signalViewStateStore = SignalViewStateStore(
            url: home.cacheRoot.deletingLastPathComponent()
                .appendingPathComponent("signal-view-state.json"))

        // The banner's way back in. `onOpenFeed` covers both "the event is
        // gone" and "the event had nowhere to go" — in either case showing the
        // record beats appearing to ignore the click.
        let bannerResponder = SignalBannerResponder(center: signalCenter)
        bannerResponder.onOpenFeed = { [weak environment] in
            environment?.isSignalFeedPresented = true
        }
        environment.signalBannerResponder = bannerResponder
        signalCenter.onInvokeAction = { [weak environment] event, action in
            guard let environment else { return }
            let hub = environment.signalEmitterHub
            if action.isDestructive {
                // Never fire a destructive action straight off a banner: the
                // user clicked a notification, not a confirmation. The feed
                // owns the confirmation dialog, so hand off to it.
                environment.isSignalFeedPresented = true
                return
            }
            SignalActionRouter(hub: hub).dispatch(event, action)
        }
        // Reading a row in-app pulls its banner out of Notification Center, so
        // the two surfaces agree about what is still outstanding.
        // Static because withdrawal touches no instance state — it asks
        // UNUserNotificationCenter directly — so there is nothing to be gained
        // from threading `makeSignalCenter`'s private channel out to here.
        signalCenter.onRead = { UserNotificationBannerChannel.withdraw(ids: $0) }
        // The read side gains its feed, mirroring `signalHub.attach(sink:)`
        // below. `signal_search` was registered at tool-assembly time, before
        // this center existed, and has been reporting the feed as unavailable
        // until now.
        signalReadAccess.attach(signalCenter)
        // Recent notable events as assistant context, alongside `host.memory`.
        // A closure, so every turn reads the feed as it is rather than a
        // snapshot taken at launch — and read-only: `SageSignalContext` calls
        // only `page` and `search`, so Sage answering "what failed today?"
        // cannot change the answer.
        _ = agentContextHub.register(appID: "host.signal") { [weak signalCenter] in
            guard let signalCenter else { return nil }
            let summary = SageSignalContext(center: signalCenter).summary()
            // An empty feed contributes NOTHING rather than a snapshot saying
            // so: a sentence asserting an absence spends context the user's
            // actual question does not get.
            guard !summary.isEmpty else { return nil }
            return AgentContextSnapshot(kind: "notifications",
                                        title: "Recent notifications",
                                        text: summary)
        }

        // External ingress (M3). Everything below is supplementary: in-process
        // emission is already wired above and is untouched by any failure here.
        let signalTokens = SignalTokenRegistry(secrets: environment.secrets)
        environment.signalTokens = signalTokens
        // Declared cross-app subscriptions (generation 10). Fan-out runs
        // AFTER the center's own delivery, so a subscribing app can never see
        // an event before the user's own surfaces do.
        let subscriptions = SignalSubscriptionRegistry(
            store: SignalSubscriptionStore(
                url: home.cacheRoot.deletingLastPathComponent()
                    .appendingPathComponent("signal-subscriptions.json")))
        environment.signalSubscriptions = subscriptions
        signalCenter.onEventRecorded = { [weak subscriptions] event in
            subscriptions?.fanOut(event)
        }

        // Load every enabled app's declared subscriptions, and register an
        // observer for the ones the user already approved.
        //
        // Approval is consulted per event inside `fanOut`, so registering an
        // observer here is not itself a grant — but the FACTORY is only called
        // for an approved app, so a refused app never even constructs one.
        for app in environment.registry.allApps where !app.declaredSignalSubscriptions.isEmpty {
            let parsed = SignalSubscription.parseReportingInvalid(
                app.declaredSignalSubscriptions, excluding: app.id)
            subscriptions.setDeclared(parsed.subscriptions, for: app.id)

            // A dropped pattern is a developer's typo, and silence would turn
            // it into a subscription that simply never fires with nothing
            // anywhere to say why.
            if !parsed.invalid.isEmpty {
                signalCenter.emit(
                    .subscriptionsDropped(displayName: app.displayName,
                                          patterns: parsed.invalid),
                    from: .host)
            }

            if subscriptions.isApproved(appID: app.id), let factory = app.signalObserverFactory {
                subscriptions.register(observer: factory(), appID: app.id)
            }
        }

        // Anything left unapproved becomes the prompt. Raised after bootstrap
        // rather than during it: the window has to exist before an overlay can
        // be shown in it, and an app whose approval is pending is simply not
        // observing in the meantime — a safe state to sit in indefinitely.
        environment.pendingSubscriptionApprovals = subscriptions.appsAwaitingApproval()

        // Pair the CLI if it is not already paired, so `ainkrad notify` works
        // out of the box rather than needing a visit to Settings first. Minted
        // once — see `ensurePaired`, which refuses to rotate a token that is
        // still good and would otherwise break every installed hook on launch.
        SignalCLIPairing.ensurePaired(registry: signalTokens)

        let ingress = SignalIngressCoordinator(
            center: signalCenter,
            tokens: signalTokens,
            limiter: SignalRateLimiter())
        let socketURL = AppEnvironment.signalSocketURL()
        let socketServer = SignalSocketServer(url: socketURL) { data in
            ingress.accept(data)
        }
        do {
            try socketServer.start()
            environment.signalSocketServer = socketServer
        } catch {
            // One warning into the feed, then carry on. A notification
            // subsystem that stops the app launching is worse than no
            // notification subsystem — the same rule `makeSignalCenter`
            // follows when the store cannot be opened.
            //
            // Recorded rather than only logged because the consequence is
            // invisible otherwise: hooks and scripts would post into nothing
            // and no one would know why.
            signalCenter.emit(.externalIngressUnavailable(reason: String(describing: error)),
                              from: .host)
        }

        // The hub was built in `bootstrapCoreStores`, before the feed existed;
        // this is where it gains something to record into.
        signalHub.attach(sink: signalCenter)
        // `RunManager` is built in `bootstrapSession`, before this runs, so the
        // center is attached rather than injected.
        environment.runManager.attachSignalCenter(signalCenter)

        // App-store outcomes into the feed. An install or update is exactly the
        // kind of thing the user starts and then looks away from, which is what
        // the feed is for.
        environment.appStoreStore.onOperationFinished = { [weak environment] operation, appID, error in
            guard let environment, let center = environment.signalCenter else { return }
            // Prefer the registry's display name; fall back to the id, which is
            // all there is for an app that failed before it registered.
            let name = environment.registry.allApps.first { $0.id == appID }?.displayName ?? appID
            switch (operation, error) {
            case (.install, nil):
                center.emit(.appInstalled(displayName: name), from: .host)
            case (.install, let error?):
                center.emit(.appInstallFailed(displayName: name,
                                              reason: Self.describe(error)), from: .host)
            case (.update, nil):
                center.emit(.appUpdated(displayName: name), from: .host)
            case (.update, let error?):
                center.emit(.appUpdateFailed(displayName: name,
                                             reason: Self.describe(error)), from: .host)
            }
        }

        // Launch-time external I/O (local-model probes, MCP connect, LSP
        // autodetect) is skipped when the app is hosting a test bundle: under
        // `xcodebuild test` these otherwise hang the shared process on network
        // timeouts / a TCC prompt, starving the tests. See
        // `AppEnvironment.isRunningUnderTests`. Guarded as one block since all
        // three are the same "background external I/O off the launch path" class.
        if !AppEnvironment.isRunningUnderTests {
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
        let runeHost = HostServicesImpl(appID: "rune", dataRootURL: pluginDataRoot,
                                            secretStore: secrets, themeManager: themeManager,
                                            hub: agentContextHub, actionHub: agentActionHub, launchHub: pluginLaunchHub, signalHub: signalHub,
                                            declaredPresentation: .pane, appAppearanceStore: appAppearanceStore)
        TerminalSettingsMigration.runIfNeeded(
            legacyRawPayload: { (persistence as? FileDocumentStore)?.rawPayloadData(forID: $0) },
            scoped: runeHost.documents, defaults: defaults)

        // Sage is a host-embedded built-in (its views read `AppEnvironment`
        // directly), scoped like any other app for its documents/secrets/theme/context.
        let sageHost = HostServicesImpl(appID: "sage", dataRootURL: pluginDataRoot,
                                             secretStore: secrets, themeManager: themeManager,
                                             hub: agentContextHub, actionHub: agentActionHub, launchHub: pluginLaunchHub, signalHub: signalHub,
                                             declaredPresentation: .pane, appAppearanceStore: appAppearanceStore)

        // Live Scry (M7 Slice 7) is likewise a host-embedded built-in — its
        // pane reads `AppEnvironment.canvasStore` directly (see `ScryApp`).
        let scryHost = HostServicesImpl(appID: "scry", dataRootURL: pluginDataRoot,
                                          secretStore: secrets, themeManager: themeManager,
                                          hub: agentContextHub, actionHub: agentActionHub, launchHub: pluginLaunchHub, signalHub: signalHub,
                                          declaredPresentation: .pane, appAppearanceStore: appAppearanceStore)

        // Hoard (M1) — a host-embedded built-in like Sage and Scry. It
        // inherits the host's unsandboxed filesystem access; its own views read
        // `AppEnvironment` directly.
        let hoardHost = HostServicesImpl(appID: "hoard", dataRootURL: pluginDataRoot,
                                         secretStore: secrets, themeManager: themeManager,
                                         hub: agentContextHub, actionHub: agentActionHub, launchHub: pluginLaunchHub, signalHub: signalHub,
                                         declaredPresentation: .pane, appAppearanceStore: appAppearanceStore)

        // Hoard' MCP server and agent context are built HERE, not in
        // `HoardApp`, for the same reason its settings are: the SDK entry
        // points are static and see only `HostServices`, while the server must
        // drive the live stores on `AppEnvironment`. Hoard is host-embedded, so
        // the host is entitled to wire it directly.
        var filesRegistration = RegisteredApp.builtIn(
            HoardApp.self,
            summary: "Browse, search and organise your files — keyboard-driven, git-aware, and wired into the assistant.",
            host: hoardHost,
            chromeFillOverride: {
                HoardApp.surfaceFill(
                    opacity: appAppearanceStore.surfaceOpacity("hoard"),
                    base: themeManager.tokens.background
                )
            })
        filesRegistration.mcpServerFactory = { [weak environment] in
            guard let environment else { return MCPAppServer(appID: HoardApp.id) }
            return HoardMCPServer.make(environment: environment)
        }

        // Publish what the user is looking at, so the assistant has the
        // browser's state without having to ask for it.
        _ = hoardHost.context.register { [weak environment] in
            guard let environment,
                  let summary = environment.filesPaneCoordinator.contextSummary else { return nil }
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
                    summary: "Your in-workspace AI assistant — chat about your code, run gated tools, and drive the terminal and git without leaving Ainkrad.",
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
                    }
                ),
                RegisteredApp.builtIn(
                    ScryApp.self,
                    summary: "The Live Scry — the assistant lays out tables, diagrams, charts, code and status as movable HUD cards.",
                    host: scryHost),
                filesRegistration
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
        if !AppEnvironment.isRunningUnderTests {
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
            Log.app.info("Restored workspace layout: \(launch.workspaces.count) of \(saved.workspaces.count) workspace(s) kept, panes \(paneState, privacy: .public), active = main")
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
                environment.workspaceManager.activeWorkspace.tileLayout.openApp(appID)
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
    }

    /// A user-facing reason string. `AppStoreError` already writes for humans;
    /// anything else falls back to its description rather than being dropped,
    /// because "failed to install" with no reason is the least useful
    /// notification the feed could carry.
    private static func describe(_ error: Error) -> String {
        if let storeError = error as? AppStoreError {
            return String(describing: storeError)
        }
        return String(describing: error)
    }
}
