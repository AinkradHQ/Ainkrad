import AinkradHostRuntime
import Foundation

/// Connects and verifies a provider. Verification is injected so the step can be
/// tested without network access; production passes `ModelCatalogService.test`.
///
/// The rule this enum exists to enforce: **verify BEFORE saving**. A saved but
/// broken connection looks configured, passes the gate, and then fails later
/// somewhere else with no obvious cause.
@MainActor
enum SetupProviders {
    enum Outcome: Equatable {
        case connected(message: String)
        /// `failure` is the probe's own classification, carried through
        /// untouched. It is what decides whether the step offers an escape —
        /// see `canDefer`. `nil` only for a failure that reached here without
        /// a probe verdict.
        case failed(message: String, failure: ConnectionFailure?)

        /// Whether this failure earns a "Set this up later" escape.
        ///
        /// The whole point of the classification: a 401 or a malformed base URL
        /// is the user's to fix and blocking them is the step doing its job; a
        /// 429, a 5xx or an unreachable endpoint is not theirs to fix, and
        /// blocking them locks them out of the app over a transient upstream
        /// failure. Read from the enum, never from `message`.
        var canDefer: Bool {
            if case .failed(_, let failure) = self { return failure?.allowsDeferral == true }
            return false
        }

        /// The single reading of "did this attempt connect?".
        ///
        /// It lives on the outcome rather than on view state so a caller can
        /// answer the question from the value it was just handed. Deriving it
        /// from a `@State` property assigned moments earlier is not the same
        /// thing: SwiftUI does not contract that a `State` write is visible to
        /// a read-back outside `body`, and a stale `true` there would leave
        /// `SetupSubscriptionFlow.pending` holding a connection
        /// `finishSubscription` had already rolled out of the store.
        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    typealias Verifier = (ProviderKind, String, ProviderCredential) async -> ConnectionTestResult

    /// API-key route. Nothing is written until the probe says ok — so a failure
    /// leaves no connection, no Keychain item, and no active-connection id.
    ///
    /// A keyless preset (`ollama`) passes `token: ""` and is probed with
    /// `.apiKey("")`, exactly as the Connections tab's Test
    /// does for a connection with no stored secret.
    static func connect(
        preset: ProviderPreset,
        token: String,
        baseURL: String,
        connections: ConnectionStore,
        agentConfig: AgentConfigStore,
        verify: Verifier
    ) async -> Outcome {
        let result = await verify(preset.kind, baseURL, .apiKey(token))
        guard result.ok else { return .failed(message: result.message, failure: result.failure) }

        let connection = connections.addConnection(
            preset: preset,
            displayName: preset.displayName,
            baseURL: baseURL,
            token: token,
            authMode: .apiKey)
        agentConfig.setActiveConnectionID(connection.id)
        return .connected(message: result.message)
    }

    /// Subscription route (OAuth sign-in and Claude Code import both land here).
    ///
    /// Unlike the API-key route this one cannot verify first: both
    /// `ClaudeOAuthLoginController` and `OAuthCredentialStore` key their token by
    /// `connection.id`, so a connection must exist before a credential can be
    /// obtained at all. The invariant is preserved by rolling back instead — a
    /// failed probe signs the credential out (clearing its Keychain item) and
    /// removes the connection, leaving the same clean slate as a failed
    /// API-key attempt. The credential is never trusted just because it came
    /// from a trusted source; it is probed like any other.
    static func finishSubscription(
        connection: Connection,
        credential: ProviderCredential,
        connections: ConnectionStore,
        agentConfig: AgentConfigStore,
        oauth: OAuthCredentialStore,
        verify: Verifier
    ) async -> Outcome {
        let result = await verify(connection.kind, connection.baseURL, credential)
        guard result.ok else {
            rollback(connection, connections: connections, agentConfig: agentConfig, oauth: oauth)
            return .failed(message: result.message, failure: result.failure)
        }
        agentConfig.setActiveConnectionID(connection.id)
        return .connected(message: result.message)
    }

    /// Undoes every write a subscription attempt can have made: the OAuth token
    /// and account entry, the connection record and its Keychain secret, and the
    /// active-connection id if it pointed here. All four are non-throwing, so
    /// there is no partial-failure window. The single owner of this teardown —
    /// the sign-in-failed path in the view calls it too, rather than keeping a
    /// second copy that could drift.
    static func rollback(
        _ connection: Connection,
        connections: ConnectionStore,
        agentConfig: AgentConfigStore,
        oauth: OAuthCredentialStore
    ) {
        oauth.signOut(connection.id)
        connections.removeConnection(connection)
        if agentConfig.activeConnectionID == connection.id {
            agentConfig.setActiveConnectionID(nil)
        }
    }

    /// What an already-configured connection is worth to this step.
    enum Adoption: Equatable {
        /// Nothing is active — the step is asked normally.
        case none
        /// An active connection exists AND passed a live probe. The step is
        /// satisfied for real and the deferral debt is settled.
        case verified(message: String)
        /// An active connection exists but did NOT pass. The user is let
        /// through anyway — they are not locked out over this — but the debt
        /// STAYS recorded, so the step is still owed and the banner still shows.
        case unverified(message: String)
    }

    /// Recognises a connection the user already has, without ever blocking on it.
    ///
    /// Two properties have to hold at once, and neither may be traded away:
    ///
    /// 1. **A user who is already correctly configured is not re-gated.** They
    ///    deferred, connected through Settings, and must not be asked to re-type
    ///    a key they already have — while the gate is up, Settings is
    ///    unreachable, so there is nowhere to point at it.
    /// 2. **A credential nobody verified does not satisfy a step whose entire
    ///    purpose is verification.** An earlier version of this asserted that
    ///    "nothing can become active without having passed a probe". That is
    ///    false: the Connections tab's Add writes a
    ///    connection AND its Keychain token with no probe at all, and
    ///    `SageModelPicker.selectConnection` makes any connection active
    ///    unconditionally. So defer → banner → Settings → add a typo'd key →
    ///    select it → relaunch would have silently cleared the debt.
    ///
    /// Both survive because the probe is **non-blocking**: it decides whether the
    /// debt is settled, never whether the user may proceed. A failure of any
    /// kind — transient or not — still lets them into the workspace, and still
    /// leaves the step owed. There is no path from here to a locked-out user.
    ///
    /// Credential resolution mirrors
    /// `SageSettingsView+Connections.testConnection` exactly: a subscription
    /// connection authenticates with its OAuth bearer, everything else with its
    /// stored key.
    static func adoptExistingConnection(
        connections: ConnectionStore,
        agentConfig: AgentConfigStore,
        oauth: OAuthCredentialStore,
        verify: Verifier
    ) async -> Adoption {
        guard let id = agentConfig.activeConnectionID,
            let connection = connections.connections.first(where: { $0.id == id })
        else { return .none }

        let credential: ProviderCredential
        if connection.authMode == .subscription {
            credential = (try? await oauth.liveCredential(for: connection)) ?? .apiKey("")
        } else {
            credential = .apiKey(connections.token(for: connection) ?? "")
        }

        let result = await verify(connection.kind, connection.baseURL, credential)
        guard result.ok else {
            return .unverified(
                message: "Using your existing \(connection.displayName) connection, "
                    + "but Ainkrad couldn't check it just now — AI features may "
                    + "not work until it does.")
        }
        return .verified(message: "Already connected · \(connection.displayName)")
    }

    /// Removes subscription connections left behind by an abandoned attempt.
    ///
    /// `SetupSubscriptionFlow.connection(connections:)` must persist a connection before OAuth can key
    /// a token to it, so a user who quits the app during the 300-second loopback
    /// wait, or who abandons the wizard with a paste outstanding, leaves an
    /// unverified keyless record on disk — "looks configured but is broken",
    /// reached outside the probe path `rollback` covers. It is never made active
    /// (so the gate stays sound), but the record should not survive.
    ///
    /// Cleanup runs when the step appears, which is the next moment the flow is
    /// reachable. The predicate is deliberately narrow: a subscription connection
    /// with NO stored OAuth account and which is not the active connection has,
    /// by construction, never passed a probe. A signed-in or active connection is
    /// never touched. This is only ever called from the first-run wizard, where
    /// the only source of connections is this step.
    @discardableResult
    static func cleanUpAbandonedSubscriptions(
        connections: ConnectionStore,
        agentConfig: AgentConfigStore,
        oauth: OAuthCredentialStore
    ) -> Int {
        let stale = connections.connections.filter {
            $0.authMode == .subscription
                && $0.id != agentConfig.activeConnectionID
                && oauth.account(for: $0.id) == nil
        }
        for connection in stale {
            rollback(connection, connections: connections, agentConfig: agentConfig, oauth: oauth)
        }
        return stale.count
    }
}

/// The subscription route's state machine, lifted OUT of the view so its
/// lifecycle is reachable from a plain applier test.
///
/// It exists because the OAuth routes are multi-step: a connection is created,
/// then a credential is acquired (possibly via a paste round-trip), then the
/// credential is probed. The bug this shape prevents: a failed paste that clears
/// the pending connection while leaving the paste field on screen, so every
/// later paste silently does nothing.
///
/// The rule: `awaitingPaste` and `pending` are only ever changed together. If the
/// paste field is shown, a connection to paste against exists.
@MainActor
final class SetupSubscriptionFlow {
    private(set) var pending: Connection?
    private(set) var awaitingPaste = false

    /// The connection this attempt authenticates against — reused across a paste
    /// round-trip so a retry never strands an orphan record.
    func connection(connections: ConnectionStore) -> Connection {
        if let pending { return pending }
        let claude = ProviderPreset.preset(id: "claude")
        let created = connections.addConnection(
            preset: claude, displayName: claude.displayName,
            baseURL: claude.defaultBaseURL, token: "", authMode: .subscription)
        pending = created
        return created
    }

    /// The loopback port couldn't bind. The flow is NOT finished: the connection
    /// stays pending and the UI must show the paste field.
    func needsPaste() { awaitingPaste = true }

    /// An attempt failed before any probe ran.
    ///
    /// A failed *paste* is exactly what the fallback exists to absorb — a
    /// mistyped code — so the flow stays intact and the next paste is a real
    /// retry. Any other failure tears the whole flow down, including the paste
    /// field, returning the user to a state they can act on ("Sign in" again)
    /// rather than to a dead button.
    func attemptFailed(
        duringPaste: Bool,
        connections: ConnectionStore,
        agentConfig: AgentConfigStore,
        oauth: OAuthCredentialStore
    ) {
        guard !duringPaste else { return }
        teardown(connections: connections, agentConfig: agentConfig, oauth: oauth)
    }

    /// A probe completed. On failure `finishSubscription` already rolled the
    /// connection back, so only the local flags are cleared here.
    func settled(connected: Bool) {
        awaitingPaste = false
        pending = connected ? pending : nil
    }

    func teardown(
        connections: ConnectionStore,
        agentConfig: AgentConfigStore,
        oauth: OAuthCredentialStore
    ) {
        if let pending {
            SetupProviders.rollback(
                pending, connections: connections,
                agentConfig: agentConfig, oauth: oauth)
        }
        pending = nil
        awaitingPaste = false
    }
}

/// The "Set this up later" offer, lifted OUT of the view so its rules are
/// reachable from a plain applier test — the same reason `SetupSubscriptionFlow`
/// lives here rather than in `SetupProvidersStepView`.
///
/// The two bugs this shape exists to prevent, both found in review:
///
/// 1. **The offer must survive the launch it causes.** A step recorded as
///    deferred re-raises the gate on itself; if the offer were derived only from
///    this session's attempts, the user would have to reproduce a transient
///    upstream failure to get past a step they had already been permitted to
///    postpone — with `.providers` first in `steps`, Back absent and the overlay
///    non-dismissible, that leaves only `⌘Q`. Hence `alreadyOwed`.
/// 2. **The offer must not be confiscated by a later mistake.** It is latched
///    (`earned`), not recomputed from the most recent attempt: an OAuth 429
///    offers it, and a subsequently mistyped API key returning 401 must not take
///    it away.
struct SetupEscape: Equatable {
    /// Seeded from `SetupCoordinator.deferredSteps` — the marker's record that
    /// this step was already postponed once.
    var alreadyOwed = false
    /// Latched by `note(_:)` the moment any attempt fails in a way the user
    /// cannot fix. Never cleared by a subsequent failure.
    private(set) var earned = false
    /// The user took the offer. Satisfies the step's requirement without a probe.
    private(set) var taken = false

    /// The ONE place a classification becomes the offer. Reads
    /// `ConnectionFailure.allowsDeferral` and nothing else — never a message.
    mutating func note(_ failure: ConnectionFailure?) {
        if failure?.allowsDeferral == true { earned = true }
    }

    mutating func take() { taken = true }

    /// A connection was established (or adopted and verified): the offer is moot
    /// and the debt is settled. `earned` is cleared too — leaving it set would
    /// re-offer the escape if the user later switched presets and cleared the
    /// outcome.
    mutating func resolve() {
        taken = false
        earned = false
        alreadyOwed = false
    }

    /// Whether "Set this up later" is on screen.
    func isOffered(isConnected: Bool) -> Bool {
        guard !taken, !isConnected else { return false }
        return earned || alreadyOwed
    }

    /// Why the offer is there. The two states need different sentences: on a
    /// relaunch with no attempt made yet there is no failure on screen, and
    /// "that failure is on the provider's side" is then a non-sequitur pointing
    /// at nothing.
    var offerCopy: String {
        earned
            ? "That failure is on the provider's side, not yours."
            : "You chose to set this up later. You can connect now, or leave it for later again."
    }
}
