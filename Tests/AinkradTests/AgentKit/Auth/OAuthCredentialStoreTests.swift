import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@MainActor @Suite struct OAuthCredentialStoreTests {
    private func makeStore(now: Date, transportResponses: [(Data, Int)]) -> (OAuthCredentialStore, InMemorySecretStore)
    {
        let secrets = InMemorySecretStore()
        let persistence = InMemoryPersistenceStore()  // existing test double
        let stub = ArrayTokenTransport(responses: transportResponses)
        let flow = ClaudeOAuthFlow(transport: stub, clientVersion: "2.1.74")
        return (
            OAuthCredentialStore(
                persistence: persistence, secrets: secrets,
                flow: flow, now: { now }), secrets
        )
    }

    @Test func storeThenReadFreshTokenSkipsRefresh() async throws {
        let now = Date(timeIntervalSince1970: 1000)
        let (store, _) = makeStore(now: now, transportResponses: [])
        let conn = Connection(
            id: UUID(), presetID: "claude", kind: .claude,
            displayName: "Claude", baseURL: "https://api.anthropic.com",
            createdAt: now, authMode: .subscription)
        store.store(
            OAuthToken(
                accessToken: "AT", refreshToken: "RT",
                expiresAt: now.addingTimeInterval(3600), scopes: ["user:inference"]),
            for: conn.id, source: .freshLogin)
        let cred = try await store.liveCredential(for: conn)
        #expect(
            cred
                == .oauth(
                    OAuthToken(
                        accessToken: "AT", refreshToken: "RT",
                        expiresAt: now.addingTimeInterval(3600),
                        scopes: ["user:inference"])))
    }

    @Test(.timeLimit(.minutes(1))) func rateLimitedRefreshKeepsExistingCredential() async throws {
        let now = Date(timeIntervalSince1970: 1000)
        let rateLimited = Data(#"{"error":{"type":"rate_limit_error"}}"#.utf8)
        let (store, _) = makeStore(now: now, transportResponses: [(rateLimited, 429)])
        let conn = Connection(
            id: UUID(), presetID: "claude", kind: .claude,
            displayName: "Claude", baseURL: "https://api.anthropic.com",
            createdAt: now, authMode: .subscription)
        let existing = OAuthToken(
            accessToken: "AT", refreshToken: "RT",
            expiresAt: now.addingTimeInterval(10),  // within skew → triggers refresh
            scopes: ["user:inference"])
        store.store(existing, for: conn.id, source: .freshLogin)
        // Refresh 429s → keep the existing credential (spec §8), do NOT throw / force re-auth.
        let cred = try await store.liveCredential(for: conn)
        #expect(cred == .oauth(existing))
    }

    @Test(.timeLimit(.minutes(1))) func expiringTokenRefreshesAndPersistsRotatedToken() async throws {
        let now = Date(timeIntervalSince1970: 1000)
        let refreshed = """
            {"access_token":"AT2","refresh_token":"RT2","expires_in":3600}
            """.data(using: .utf8)!
        let (store, _) = makeStore(now: now, transportResponses: [(refreshed, 200)])
        let conn = Connection(
            id: UUID(), presetID: "claude", kind: .claude,
            displayName: "Claude", baseURL: "https://api.anthropic.com",
            createdAt: now, authMode: .subscription)
        store.store(
            OAuthToken(
                accessToken: "AT", refreshToken: "RT",
                expiresAt: now.addingTimeInterval(10), scopes: ["user:inference"]),
            for: conn.id, source: .freshLogin)  // expires within skew
        let cred = try await store.liveCredential(for: conn)
        guard case .oauth(let t) = cred else {
            Issue.record("expected oauth")
            return
        }
        #expect(t.accessToken == "AT2")
        #expect(t.refreshToken == "RT2")
        // Persisted: a second read returns the rotated token without another refresh.
        let again = try await store.liveCredential(for: conn)
        #expect(again == .oauth(t))
    }
}
