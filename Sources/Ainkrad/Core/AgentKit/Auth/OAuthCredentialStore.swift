import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/Auth/OAuthCredentialStore.swift
import Foundation

/// `@MainActor` façade for subscription OAuth: persists token VALUES in the
/// Keychain (via `SecretStore`, JSON-encoded blob under `oauthSecretID`), tracks
/// non-secret `OAuthAccount` metadata in the `OAuthAccountsDocument`, and does
/// single-flight refresh-on-read so concurrent callers share one network call.
@MainActor
final class OAuthCredentialStore {
    private let persistence: PersistenceStore
    private let secrets: SecretStore
    private let flow: ClaudeOAuthFlow
    private let now: () -> Date
    private var doc: OAuthAccountsDocument
    private var inFlight: [String: Task<OAuthToken, Error>] = [:]

    init(
        persistence: PersistenceStore, secrets: SecretStore,
        flow: ClaudeOAuthFlow, now: @escaping () -> Date = Date.init
    ) {
        self.persistence = persistence
        self.secrets = secrets
        self.flow = flow
        self.now = now
        self.doc = persistence.load(OAuthAccountsDocument.self) ?? OAuthAccountsDocument()
    }

    func account(for connectionID: UUID) -> OAuthAccount? {
        doc.accountsByConnection[connectionID.uuidString]
    }

    func store(_ token: OAuthToken, for connectionID: UUID, source: OAuthSource) {
        writeToken(token, for: connectionID)
        doc.accountsByConnection[connectionID.uuidString] = OAuthAccount(
            provider: "anthropic", expiresAt: token.expiresAt, scopes: token.scopes,
            source: source, email: nil, displayName: nil)
        persistence.save(doc)
    }

    func signOut(_ connectionID: UUID) {
        secrets.setSecret(nil, for: oauthSecretID(connectionID))
        doc.accountsByConnection[connectionID.uuidString] = nil
        persistence.save(doc)
    }

    func liveCredential(for connection: Connection) async throws -> ProviderCredential {
        let token = try await validToken(for: connection.id)
        return .oauth(token)
    }

    // MARK: - Internals

    private func validToken(for connectionID: UUID) async throws -> OAuthToken {
        guard let token = readToken(for: connectionID) else {
            throw ClaudeOAuthError.malformedResponse  // no stored token → treat as needs-login
        }
        guard token.isExpiring(now: now()) else { return token }

        let key = connectionID.uuidString
        do {
            let refreshed: OAuthToken
            if let existing = inFlight[key] {
                refreshed = try await existing.value
            } else {
                let task = Task<OAuthToken, Error> { [flow] in
                    try await flow.refresh(refreshToken: token.refreshToken)
                }
                inFlight[key] = task
                defer { inFlight[key] = nil }
                refreshed = try await task.value
                store(refreshed, for: connectionID, source: account(for: connectionID)?.source ?? .freshLogin)
            }
            return refreshed
        } catch ClaudeOAuthError.tokenEndpoint(status: 429, _) {
            // Rate-limited refresh (spec §8): the credential is still valid — keep using
            // it, don't force re-auth. The token may be within the refresh skew but not
            // yet actually expired; let the inference attempt proceed on it.
            return token
        }
    }

    private func writeToken(_ token: OAuthToken, for connectionID: UUID) {
        let data: Data
        do {
            data = try JSONEncoder().encode(token)
        } catch {
            // The sign-in succeeded but the token can't be kept: say so instead of dropping it silently.
            Log.settings.error(
                "OAuth token for \(connectionID, privacy: .public) was not saved: \(String(describing: error), privacy: .public)"
            )
            return
        }
        guard let json = String(data: data, encoding: .utf8) else {
            Log.settings.error("OAuth token for \(connectionID, privacy: .public) was not saved: encoded token is not UTF-8")
            return
        }
        secrets.setSecret(json, for: oauthSecretID(connectionID))
    }

    private func readToken(for connectionID: UUID) -> OAuthToken? {
        guard let json = secrets.secret(for: oauthSecretID(connectionID)),
            let data = json.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(OAuthToken.self, from: data)
    }
}
