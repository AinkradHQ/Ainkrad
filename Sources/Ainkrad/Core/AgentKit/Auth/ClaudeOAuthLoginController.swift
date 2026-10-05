import AppKit
// Sources/Ainkrad/Core/AgentKit/Auth/ClaudeOAuthLoginController.swift
import Foundation

/// Orchestrates the subscription OAuth login flow for the settings UI:
/// PKCE + state → open the browser authorize URL → loopback callback (falling
/// back to a pasted code/URL when the loopback port can't bind) → token
/// exchange → persisted via `OAuthCredentialStore`. Also supports importing an
/// existing Claude Code CLI login in place of a fresh browser round-trip.
@MainActor
final class ClaudeOAuthLoginController: ObservableObject {
    private let store: OAuthCredentialStore
    private let flow: ClaudeOAuthFlow
    private let importer: ClaudeCodeCredentialImporter
    private var pendingPKCE: PKCE?
    private var pendingState: String?

    @Published var authorizeURL: URL?
    @Published var usePasteFallback = false
    @Published var errorMessage: String?
    /// The machine-readable reading of the same failure `errorMessage` describes.
    ///
    /// The OAuth route reaches its verdict from a DIFFERENT subsystem than the
    /// model-catalog probe (a token exchange, not a `/models` call), but both
    /// land on `ConnectionFailure` — the token endpoint's status goes through
    /// `ConnectionFailure.forHTTP`, exactly as the probe's does — so the wizard
    /// makes one decision from one predicate for both routes.
    @Published var errorFailure: ConnectionFailure?

    init(
        store: OAuthCredentialStore,
        flow: ClaudeOAuthFlow,
        importer: ClaudeCodeCredentialImporter = ClaudeCodeCredentialImporter()
    ) {
        self.store = store
        self.flow = flow
        self.importer = importer
    }

    var canImportFromClaudeCode: Bool { importer.isAvailable }

    /// Pure parser for a pasted callback: a full redirect URL
    /// (`…/callback?code=…&state=…`), a `code#state` pair, or a bare code.
    /// Empty/whitespace-only input yields `nil`.
    nonisolated static func parsePastedCode(_ raw: String) -> CallbackResult? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if let comps = URLComponents(string: s), comps.queryItems?.contains(where: { $0.name == "code" }) == true {
            return try? LoopbackCallbackServer.parseCallback(query: comps.query ?? "")
        }
        let parts = s.split(separator: "#", maxSplits: 1).map(String.init)
        return CallbackResult(code: parts[0], state: parts.count > 1 ? parts[1] : "")
    }

    func beginLogin(for connection: Connection) async {
        errorMessage = nil
        errorFailure = nil
        let pkce = PKCE.generate()
        let state = UUID().uuidString
        pendingPKCE = pkce
        pendingState = state
        let url = ClaudeOAuthFlow.authorizeURL(state: state, challenge: pkce.challenge)
        authorizeURL = url
        NSWorkspace.shared.open(url)

        let server = LoopbackCallbackServer()
        do {
            let cb = try await server.waitForCallback(timeout: 300)
            try await complete(cb, for: connection)
        } catch LoopbackError.bindFailed {
            usePasteFallback = true  // UI shows the paste field + authorizeURL
        } catch {
            report(error)
        }
    }

    func pasteCode(_ raw: String, for connection: Connection) async {
        errorMessage = nil
        errorFailure = nil
        do {
            guard let cb = Self.parsePastedCode(raw) else { throw LoopbackError.malformedCallback }
            try await complete(cb, for: connection)
        } catch {
            report(error)
        }
    }

    func importFromClaudeCode(for connection: Connection) {
        errorMessage = nil
        errorFailure = nil
        do {
            let token = try importer.load()
            store.store(token, for: connection.id, source: .claudeCodeImport)
        } catch {
            report(error)
        }
    }

    /// Sets `errorMessage`/`errorFailure` from one error, and sends the raw
    /// diagnostic detail to the log instead of the screen.
    ///
    /// Only the token endpoint carries a body, and for a FAILED exchange that
    /// body is an error envelope (`{"error":…,"error_description":…}`) — never a
    /// token, and never the user's credential, which travels only in the
    /// request. It is logged (truncated) so the failure stays diagnosable, and
    /// it is the one thing on the sign-in screen that used to be rendered
    /// verbatim.
    private func report(_ error: Error) {
        if case ClaudeOAuthError.tokenEndpoint(let status, let body) = error, !body.isEmpty {
            Log.settings.error(
                "Claude OAuth token endpoint \(status, privacy: .public): \(String(body.prefix(300)), privacy: .public)"
            )
        }
        errorMessage = Self.message(for: error)
        errorFailure = Self.classify(error)
    }

    /// User-facing copy: what happened, and what to do next. No raw body, no
    /// status code standing in for an explanation.
    static func message(for error: Error) -> String {
        switch error {
        case LoopbackError.malformedCallback:
            return "That code or link didn't look right. Try pasting it again."
        case ClaudeOAuthError.tokenEndpoint(let status, _):
            switch ConnectionFailure.forHTTP(status: status) {
            case .rateLimited:
                return "Claude is rate-limiting sign-ins right now. This is temporary and "
                    + "nothing is wrong with your account — wait a minute and try again, or "
                    + "use your existing Claude Code login or an API key instead."
            case .serverError:
                return "Claude's sign-in service is having trouble on its end. This is "
                    + "temporary — try again shortly, or connect with an API key instead."
            case .unauthorized:
                return "Claude turned down that sign-in. Start it again and approve the "
                    + "request in the browser, making sure you paste the whole code back."
            default:
                return "Claude couldn't complete that sign-in. Start it again, or connect "
                    + "with an API key instead. (The details are in the app log.)"
            }
        case ClaudeOAuthError.allEndpointsFailed:
            return "Couldn't reach Claude to sign in. Check your internet connection and "
                + "try again."
        case ClaudeOAuthError.malformedResponse:
            return "Claude sent back a sign-in response Ainkrad didn't understand. Try "
                + "again, or connect with an API key instead."
        default:
            return "Sign-in failed: \(error.localizedDescription)"
        }
    }

    /// The same verdict, as a value. A token-endpoint status is classified by
    /// `ConnectionFailure.forHTTP` — the identical function the model-catalog
    /// probe uses — so a 429 means the same thing on both routes. `nil` means
    /// "not a connection failure": a mistyped paste is the user's to redo here
    /// and now, and must not offer to postpone the step.
    static func classify(_ error: Error) -> ConnectionFailure? {
        switch error {
        case LoopbackError.malformedCallback:
            return nil
        case ClaudeOAuthError.tokenEndpoint(let status, _):
            return .forHTTP(status: status)
        case ClaudeOAuthError.allEndpointsFailed:
            return .unreachable
        case ClaudeOAuthError.malformedResponse:
            return nil
        default:
            return nil
        }
    }

    private func complete(_ cb: CallbackResult, for connection: Connection) async throws {
        guard let pkce = pendingPKCE, let state = pendingState else { throw LoopbackError.malformedCallback }
        guard cb.state.isEmpty || cb.state == state else { throw LoopbackError.malformedCallback }  // CSRF guard
        let token = try await flow.exchange(code: cb.code, verifier: pkce.verifier, state: state)
        store.store(token, for: connection.id, source: .freshLogin)
        pendingPKCE = nil
        pendingState = nil
        usePasteFallback = false
    }
}
