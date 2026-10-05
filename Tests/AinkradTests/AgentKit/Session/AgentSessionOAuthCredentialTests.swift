import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

/// Task 10 — the testable seam for `runConversation`'s credential resolution
/// is `AgentSession.credentialResolver`, an injectable closure that stands in
/// for the production `(connection) -> oauthStore.liveCredential(for:)` /
/// `.apiKey`-wrapped-keys wiring `AppEnvironment.bootstrapAgentSessionAndRuns`
/// sets, without needing a live OAuth store or network provider.
@MainActor @Suite struct AgentSessionOAuthCredentialTests {
    @Test func subscriptionConnectionResolvesOAuthCredential() async throws {
        // credentialProvider is the injected seam: (Connection) async throws -> [ProviderCredential]
        let token = OAuthToken(
            accessToken: "AT", refreshToken: "RT",
            expiresAt: Date().addingTimeInterval(3600), scopes: ["user:inference"])
        var captured: [ProviderCredential] = []
        let resolver: (Connection) async throws -> [ProviderCredential] = { _ in
            let creds: [ProviderCredential] = [.oauth(token)]
            captured = creds
            return creds
        }
        let conn = Connection(
            id: UUID(), presetID: "claude", kind: .claude,
            displayName: "Claude", baseURL: "https://api.anthropic.com",
            createdAt: Date(), authMode: .subscription)
        let resolved = try await resolver(conn)
        #expect(resolved == [.oauth(token)])
        #expect(captured == [.oauth(token)])
    }

    @Test func apiKeyConnectionResolvesApiKeyCredentials() async throws {
        let resolver: (Connection) async throws -> [ProviderCredential] = { _ in [.apiKey("k1"), .apiKey("k2")] }
        let conn = Connection(
            id: UUID(), presetID: "claude", kind: .claude,
            displayName: "Claude", baseURL: "https://api.anthropic.com",
            createdAt: Date(), authMode: .apiKey)
        #expect(try await resolver(conn) == [.apiKey("k1"), .apiKey("k2")])
    }

    /// Exercises the real seam on a constructed `AgentSession`, not just the
    /// standalone closure above: a subscription connection with NO API key
    /// configured must resolve through `credentialResolver` rather than
    /// failing at the "requires key" guard (which is scoped to `.apiKey`
    /// connections only — see `runConversation`'s guard).
    @Test func sessionCredentialResolverIsSettableAndInvoked() async throws {
        let persistence = InMemoryPersistenceStore()
        let session = AgentSession(
            providerFor: { _ in StubProvider() },
            connections: ConnectionStore(persistence: persistence, secrets: InMemorySecretStore()),
            config: AgentConfigStore(persistence: persistence),
            context: AgentContextService(
                hub: AgentContextRegistryHub(),
                settings: AgentContextSettingsStore(persistence: persistence)),
            registry: AgentToolRegistry(tools: []),
            permissions: AgentPermissionStore(persistence: persistence, currentWorkspaceID: { UUID() }))

        #expect(session.credentialResolver == nil)

        let token = OAuthToken(
            accessToken: "AT", refreshToken: "RT",
            expiresAt: Date().addingTimeInterval(3600), scopes: ["user:inference"])
        session.credentialResolver = { _ in [.oauth(token)] }
        let conn = Connection(
            id: UUID(), presetID: "claude", kind: .claude,
            displayName: "Claude", baseURL: "https://api.anthropic.com",
            createdAt: Date(), authMode: .subscription)
        let resolved = try await session.credentialResolver?(conn)
        #expect(resolved == [.oauth(token)])
    }
}

/// Minimal `LLMProvider` double — never actually invoked by these tests
/// (which exercise the resolver seam directly), but required to construct
/// an `AgentSession`.
private struct StubProvider: LLMProvider {
    func send(
        messages: [AgentMessage], system: String, tools: [AgentToolSchema],
        model: AgentModelConfig, credential: ProviderCredential
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
