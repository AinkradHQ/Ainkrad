import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// The Providers step — the one step the user cannot pass without a working AI
/// connection. Continue is enabled only after a probe returned ok.
///
/// Three routes, all of which reach the same probe:
/// 1. Import an existing Claude Code login (shown only when the importer says a
///    login exists; the check is prompt-free).
/// 2. Sign in with Claude (loopback OAuth, paste fallback when the port can't
///    bind).
/// 3. Paste an API key for any `ProviderPreset`.
///
/// The token is never rendered back (`AinkradSecureField` only), never logged, and
/// never interpolated into a message — every message shown here is either a
/// literal or `ConnectionTestResult.message`, which is documented to redact the
/// key.
struct SetupProvidersStepView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.setupGroupWidth) private var groupWidth

    let coordinator: SetupCoordinator

    @State private var preset = ProviderPreset.preset(id: "openai")
    @State private var token = ""
    @State private var baseURL = ProviderPreset.preset(id: "openai").defaultBaseURL
    @State private var isBusy = false
    @State private var outcome: SetupProviders.Outcome?
    @State private var pasteText = ""
    @State private var oauthController: ClaudeOAuthLoginController?
    @State private var flow = SetupSubscriptionFlow()
    @State private var flowRevision = 0  // redraw trigger; the flow is not @Observable
    @State private var routeError: String?
    /// The OAuth route's classification of `routeError`, kept beside it so the
    /// escape decision is made from a value and not from the string.
    @State private var routeFailure: ConnectionFailure?
    /// The escape offer's whole state — latched, seeded from the marker, and
    /// tested directly (`SetupEscape`) rather than re-implemented here.
    @State private var escape = SetupEscape()
    /// Set when an already-active connection was adopted but could NOT be
    /// verified. The user is let through; the step stays owed.
    @State private var adoptionWarning: String?

    /// True once ANY route has established a verified connection during this
    /// step. Separate from `outcome`, which is the last attempt's message and is
    /// deliberately cleared when the user switches provider.
    ///
    /// Without this, connecting a provider and then merely SWITCHING the picker
    /// disabled Continue — the requirement was being read from a transient
    /// message rather than from whether a connection exists. Connecting a second
    /// provider and having it fail did the same thing, throwing away a working
    /// first connection.
    @State private var hasVerifiedConnection = false

    /// View-level convenience only (Continue's enablement, clearing the token
    /// field). Decisions made inside async work read the returned
    /// `SetupProviders.Outcome` directly — see `settleSubscription`.
    ///
    /// Latched: once something has verified, a later failed attempt at a
    /// DIFFERENT provider cannot un-connect the user.
    private var isConnected: Bool { hasVerifiedConnection || (outcome?.isConnected ?? false) }

    /// Every connection saved so far, which is the persistent answer to "what
    /// have I connected". Read from the store rather than from this view's own
    /// state, because the store is what survives switching provider, leaving the
    /// step and coming back to it.
    private var savedConnections: [Connection] {
        environment.connectionStore.connections
    }

    /// The presets that already have a saved connection, so a route can say so
    /// instead of presenting an empty key field for something already done.
    private var connectedPresetIDs: Set<String> {
        Set(savedConnections.map(\.presetID))
    }

    /// The rule and its copy live in `SetupValidation`, not here.
    private var unmet: [SetupValidation.Requirement] {
        SetupValidation.unmet(
            for: .providers,
            values: [
                "isConnected": isConnected ? "true" : "false",
                "isDeferred": escape.taken ? "true" : "false",
            ])
    }

    /// Whether "Set this up later" is on screen.
    ///
    /// Read ONLY from `ConnectionFailure.allowsDeferral`, reached either through
    /// the probe's `SetupProviders.Outcome` or through the OAuth controller's
    /// `errorFailure` — never by inspecting the message that happens to be
    /// displayed next to it.
    ///
    /// Both the rule and the latch live on `SetupEscape`; this only asks it.
    private var canDefer: Bool { escape.isOffered(isConnected: isConnected) }

    var body: some View {
        let tokens = environment.themeManager.tokens

        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro(tokens: tokens)
                    SetupConnectedList(connections: savedConnections, tokens: tokens) {
                        environment.connectionStore.removeConnection($0)
                    }
                    claudeRoutes(tokens: tokens)
                    apiKeyRoute(tokens: tokens)
                    status(tokens: tokens)
                    deferAffordance(tokens: tokens)
                }
                .padding(20)
                // FILLS the group, exactly as the Home step's folder listing
                // does. Capping the whole column instead left every panel hard
                // against the left edge with a void beside it — the layout read
                // as broken rather than as composed, because the empty space was
                // INSIDE the group rather than around it.
                //
                // Prose within the column is capped individually; see the
                // section hints.
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Back matters most on THIS step: it is mandatory and the
            // requirement is a live probe the user may simply not be able to
            // pass. Without Back, a failing connection is a dead end. It is
            // therefore not gated on `isConnected` — only Continue is.
            SetupStepFooter(
                coordinator: coordinator,
                isPrimaryDisabled: !unmet.isEmpty
            ) {
                coordinator.advance()
            }
        }
        .onAppear {
            if oauthController == nil {
                oauthController = ClaudeOAuthLoginController(
                    store: environment.oauthStore,
                    flow: ClaudeOAuthFlow(clientVersion: ClaudeProvider.claudeCodeVersion))
                // Clear anything an abandoned attempt (quit during the loopback
                // wait, wizard left with a paste outstanding) left on disk.
                SetupProviders.cleanUpAbandonedSubscriptions(
                    connections: environment.connectionStore,
                    agentConfig: environment.agentConfigStore,
                    oauth: environment.oauthStore)
                // Seeded from the marker, so an offer already earned in a
                // previous session is on screen before anything is attempted.
                escape.alreadyOwed = coordinator.deferredSteps.contains(.providers)
                Task { await adoptExistingConnection() }
            }
        }
    }

    // MARK: - Sections

    private func intro(tokens: DesignTokens) -> some View {
        Text(
            "Ainkrad needs one working AI connection before it can do anything. "
                + "Connect a provider below — the connection is tested before it's saved, "
                + "so nothing broken gets stored."
        )
        .font(AinkradFont.display(12))
        .foregroundStyle(tokens.foreground.opacity(0.6))
        .fixedSize(horizontal: false, vertical: true)
        // Prose is capped even though the column fills, so the provider rows
        // below can use the room without the intro running with them.
        .frame(
            maxWidth: SetupStageLayout.readingWidth(inGroupOf: groupWidth),
            alignment: .leading)
    }

    /// Switching preset resets the key field and the base URL to the new
    /// preset's, and clears the last attempt's MESSAGE only. It used to clear
    /// the connected state with it, so switching provider silently un-did a
    /// working connection and disabled Continue. What survives is
    /// `hasVerifiedConnection` and the store itself.
    private var presetSelection: Binding<String> {
        Binding(
            get: { preset.id },
            set: { id in
                let p = ProviderPreset.preset(id: id)
                preset = p
                baseURL = p.defaultBaseURL
                token = ""
                outcome = nil
            })
    }

    private func claudeRoutes(tokens: DesignTokens) -> some View {
        SetupClaudeRoutes(
            tokens: tokens,
            canImport: oauthController?.canImportFromClaudeCode == true,
            isBusy: isBusy,
            awaitingPaste: flow.awaitingPaste,
            authorizeURL: oauthController?.authorizeURL,
            routeError: routeError,
            pasteText: $pasteText,
            onImport: { Task { await runImport() } },
            onSignIn: { Task { await runSignIn() } },
            onPaste: { raw in Task { await runPaste(raw) } })
    }

    private func apiKeyRoute(tokens: DesignTokens) -> some View {
        SetupAPIKeyRoute(
            tokens: tokens,
            preset: preset,
            presetSelection: presetSelection,
            baseURL: $baseURL,
            token: $token,
            isPresetConnected: connectedPresetIDs.contains(preset.id),
            isBusy: isBusy,
            canConnect: canConnect,
            onConnect: { Task { await runAPIKey() } })
    }

    /// A keyless preset (ollama) needs only a base URL; everything else needs a key.
    private var canConnect: Bool {
        let hasKey = !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasURL = !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasURL && (!preset.requiresKey || hasKey)
    }

    /// The escape hatch, shown ONLY for a failure the user cannot fix.
    ///
    /// The step stays required by default; this is not a general "skip". It
    /// appears when — and only when — the classification carried out of the
    /// probe (or out of the OAuth token exchange) says the failure was
    /// transient: rate limiting, a provider 5xx, an unreachable endpoint. A 401
    /// or a malformed base URL is the user's to fix and gets no button, because
    /// fixing it is the entire point of this step.
    ///
    /// Deferring writes nothing: verify-before-save means the failed attempt
    /// already left no connection, and this path adds none. The user lands in
    /// the workspace with AI off, a persistent banner, and the step still owed.
    @ViewBuilder
    private func deferAffordance(tokens: DesignTokens) -> some View {
        if escape.taken {
            SetupProviderStatusRow(
                tokens: tokens, icon: "clock.badge.exclamationmark",
                text: adoptionWarning
                    ?? "Set up later. Ainkrad's AI features stay off until you connect a "
                    + "provider — you'll be reminded in the workspace.",
                color: tokens.accentTertiary
            )
            .accessibilityIdentifier("setup.providers.deferred")
        } else if canDefer {
            VStack(alignment: .leading, spacing: 6) {
                Text(escape.offerCopy)
                    .font(AinkradFont.display(11))
                    .foregroundStyle(tokens.foreground.opacity(0.55))
                AinkradButton(title: "Set this up later", style: .secondary) {
                    // One act: walked past AND recorded as still owed.
                    escape.take()
                    coordinator.setDeferred(.providers, true)
                }
                .accessibilityIdentifier("setup.providers.defer")
            }
        }
    }

    @ViewBuilder
    private func status(tokens: DesignTokens) -> some View {
        switch outcome {
        case .connected(let message):
            SetupProviderStatusRow(
                tokens: tokens, icon: "checkmark.seal.fill",
                text: message, color: tokens.accentSecondary)
        case .failed(let message, _):
            SetupProviderStatusRow(
                tokens: tokens, icon: "exclamationmark.triangle.fill",
                text: message, color: tokens.accentTertiary)
        case nil:
            // `routeError` is rendered inside the Claude section now, beside the
            // route that produced it. Repeating it here would print the same
            // failure twice on one screen.
            if routeError == nil, let message = unmet.first?.message {
                // Nothing attempted yet: Continue is off and, without this,
                // nothing on screen says why. The copy comes from
                // `SetupValidation` like every other requirement message — this
                // step's requirement being a probe rather than a field changes
                // nothing about where the rule lives.
                SetupRequirementNote(message: message, tokens: tokens)
                    .accessibilityIdentifier("setup.providers.isConnected.requirement")
            }
        }
    }

    // MARK: - Routes

    private func runAPIKey() async {
        guard canConnect, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        routeError = nil
        routeFailure = nil
        let service = environment.modelCatalogService
        // Same read-back rule as `settleSubscription`: decide from the returned
        // value, not from the `@State` just assigned. Harmless here (a stale
        // read only leaves the field populated) but the two routes should not
        // disagree about how they read their own result.
        let result = await SetupProviders.connect(
            preset: preset, token: token, baseURL: baseURL,
            connections: environment.connectionStore,
            agentConfig: environment.agentConfigStore,
            verify: { kind, url, credential in
                await service.test(kind: kind, baseURL: url, credential: credential)
            })
        outcome = result
        if case .failed(_, let failure) = result { escape.note(failure) }
        if result.isConnected {
            hasVerifiedConnection = true
            token = ""
            clearDeferral()
        }
    }

    private func runImport() async {
        guard let controller = oauthController, !isBusy else { return }
        isBusy = true
        defer {
            isBusy = false
            flowRevision += 1
        }
        let connection = flow.connection(connections: environment.connectionStore)
        controller.importFromClaudeCode(for: connection)
        await settleSubscription(connection, controller: controller, duringPaste: false)
    }

    private func runSignIn() async {
        guard let controller = oauthController, !isBusy else { return }
        isBusy = true
        defer {
            isBusy = false
            flowRevision += 1
        }
        let connection = flow.connection(connections: environment.connectionStore)
        await controller.beginLogin(for: connection)
        // `beginLogin` never throws and returns nothing: a loopback bind failure
        // sets `usePasteFallback`, in which case the flow is not finished yet and
        // the connection stays pending for `runPaste`.
        if controller.usePasteFallback {
            flow.needsPaste()
            // Surface (rather than discard) whatever the controller last said, so
            // "nothing happened" is never indistinguishable from a real error.
            routeError = controller.errorMessage
            routeFailure = controller.errorFailure
            escape.note(controller.errorFailure)
            return
        }
        await settleSubscription(connection, controller: controller, duringPaste: false)
    }

    private func runPaste(_ raw: String) async {
        guard let controller = oauthController, !isBusy else { return }
        // The flow guarantees a pending connection whenever the paste field is
        // shown. If that ever fails to hold, say so rather than doing nothing.
        guard let connection = flow.pending else {
            routeError = "That sign-in attempt has expired. Start it again with Sign in with Claude."
            // A stale flow is not a provider failure: nothing about it says the
            // step should be postponable, so no escape is offered for it.
            routeFailure = nil
            flow.settled(connected: false)
            flowRevision += 1
            return
        }
        isBusy = true
        defer {
            isBusy = false
            flowRevision += 1
        }
        await controller.pasteCode(raw, for: connection)
        await settleSubscription(connection, controller: controller, duringPaste: true)
    }

    /// Resolves a subscription credential exactly the way
    /// `SageSettingsView+Connections.testConnection` does, probes it, and
    /// commits or rolls back.
    private func settleSubscription(
        _ connection: Connection,
        controller: ClaudeOAuthLoginController,
        duringPaste: Bool
    ) async {
        if let message = controller.errorMessage {
            routeError = message
            // The OAuth subsystem's own verdict, already expressed as a
            // `ConnectionFailure` by `ClaudeOAuthLoginController.classify`, so
            // this route reaches the same decision as the API-key route without
            // either of them reading the other's copy.
            routeFailure = controller.errorFailure
            escape.note(controller.errorFailure)
            // A failed paste keeps the route retryable — a mistyped code is the
            // exact case the fallback exists for. Any other failure tears the
            // flow down so the user is returned to the sign-in button.
            flow.attemptFailed(
                duringPaste: duringPaste,
                connections: environment.connectionStore,
                agentConfig: environment.agentConfigStore,
                oauth: environment.oauthStore)
            return
        }
        let service = environment.modelCatalogService
        let oauthStore = environment.oauthStore
        let credential = (try? await oauthStore.liveCredential(for: connection)) ?? .apiKey("")

        // Bound to a local first. `flow.settled` must be told what
        // `finishSubscription` ACTUALLY returned, not what `@State outcome`
        // reads back as — the write below is not contractually visible to a
        // read outside `body`, and a stale `true` would keep `flow.pending`
        // holding a connection the failed probe had already removed from the
        // store, handing OAuth a dead connection id on the next attempt.
        let settled = await SetupProviders.finishSubscription(
            connection: connection, credential: credential,
            connections: environment.connectionStore,
            agentConfig: environment.agentConfigStore,
            oauth: oauthStore,
            verify: { kind, url, cred in
                await service.test(kind: kind, baseURL: url, credential: cred)
            })
        outcome = settled
        routeError = nil
        routeFailure = nil
        if case .failed(_, let failure) = settled { escape.note(failure) }
        if settled.isConnected {
            hasVerifiedConnection = true
            clearDeferral()
        }
        flow.settled(connected: settled.isConnected)
    }

    /// A working connection cancels any earlier deferral — including one made in
    /// a previous session, which is exactly the case when the user came back
    /// here through the workspace banner. Without this the marker would keep
    /// owing the step and the gate would greet them again forever.
    private func clearDeferral() {
        escape.resolve()
        coordinator.setDeferred(.providers, false)
    }

    /// Recognises a connection this user already has — see
    /// `SetupProviders.adoptExistingConnection` for why the probe is
    /// non-blocking and what each verdict means.
    ///
    /// Neither verdict can gate the user: `.verified` satisfies the step, and
    /// `.unverified` lets them through while KEEPING the debt, so the banner
    /// stays up and the step is asked again rather than being silently satisfied
    /// by a credential nobody ever checked.
    private func adoptExistingConnection() async {
        guard outcome == nil else { return }
        let service = environment.modelCatalogService
        let adoption = await SetupProviders.adoptExistingConnection(
            connections: environment.connectionStore,
            agentConfig: environment.agentConfigStore,
            oauth: environment.oauthStore,
            verify: { kind, url, credential in
                await service.test(kind: kind, baseURL: url, credential: credential)
            })
        switch adoption {
        case .none:
            break
        case .verified(let message):
            outcome = .connected(message: message)
            hasVerifiedConnection = true
            clearDeferral()
        case .unverified(let message):
            adoptionWarning = message
            // Walked past, still owed — the same pairing the explicit escape
            // makes, so the marker and the screen agree.
            escape.take()
            coordinator.setDeferred(.providers, true)
        }
    }
}
