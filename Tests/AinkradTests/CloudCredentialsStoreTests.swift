import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("CloudCredentialsStore")
@MainActor
struct CloudCredentialsStoreTests {
    // Uses the REAL in-memory SecretStore that already ships in
    // Sources/Ainkrad/Core/Persistence/SecretStore.swift (verified) — never
    // the real Keychain in tests.

    @Test func reportsUnconfiguredByDefault() {
        let s = CloudCredentialsStore(secrets: InMemorySecretStore())
        #expect(s.isConfigured(.modal) == false)
        #expect(s.credential(for: .modal) == nil)
    }

    @Test func storesAndReadsPerProvider() {
        let s = CloudCredentialsStore(secrets: InMemorySecretStore())
        s.setCredential("tok_123", for: .modal)
        #expect(s.isConfigured(.modal))
        #expect(s.credential(for: .modal) == "tok_123")
        #expect(s.isConfigured(.daytona) == false)  // isolated per provider
    }

    @Test func nilCredentialDeletes() {
        let s = CloudCredentialsStore(secrets: InMemorySecretStore())
        s.setCredential("tok", for: .modal)
        s.setCredential(nil, for: .modal)
        #expect(s.isConfigured(.modal) == false)
    }

    @Test func emptyStringCredentialIsTreatedAsUnconfigured() {
        let s = CloudCredentialsStore(secrets: InMemorySecretStore())
        s.setCredential("", for: .modal)
        #expect(s.isConfigured(.modal) == false)
    }

    @Test func credentialGoesThroughSecretStoreByKeyNotAnySeparateDocument() {
        // Verifies creds are stored ONLY under the SecretStore, keyed per
        // provider — nothing else (e.g. a SandboxProfile) is touched.
        let secrets = InMemorySecretStore()
        let s = CloudCredentialsStore(secrets: secrets)
        s.setCredential("tok_abc", for: .singularity)
        #expect(secrets.secret(for: "cloud.singularity.token") == "tok_abc")
        #expect(secrets.secret(for: "cloud.modal.token") == nil)
    }
}

@Suite("StubCloudSandboxBackend — fail-closed unconfigured")
@MainActor
struct StubCloudSandboxBackendTests {
    @Test func unconfiguredBackendIsUnavailable() async {
        let credentials = CloudCredentialsStore(secrets: InMemorySecretStore())
        let backend = StubCloudSandboxBackend(provider: .modal, credentials: credentials)
        #expect(await backend.isAvailable() == false)
    }

    @Test func unconfiguredRunReturnsFailedResultWithGuidanceAndDoesNotExecute() async throws {
        let credentials = CloudCredentialsStore(secrets: InMemorySecretStore())
        let backend = StubCloudSandboxBackend(provider: .modal, credentials: credentials)

        let request = ExecutionRequest(
            command: "echo should-not-run",
            workingDir: nil,
            profile: BuiltInSandboxProfiles.workspaceWrite)
        let result = try await backend.run(request)

        #expect(result.isError)
        #expect(result.exitCode != 0)
        #expect(result.output.lowercased().contains("not configured"))
        // The failed result carries only guidance text — never an echo of
        // any credential value (there is none configured here, but this
        // also guards against a future regression that interpolates one in).
        #expect(!result.output.contains("tok_"))
    }

    @Test func configuredBackendIsAvailableButWakeStillFailsClosedResearchItem() async {
        let credentials = CloudCredentialsStore(secrets: InMemorySecretStore())
        credentials.setCredential("tok_123", for: .modal)
        let backend = StubCloudSandboxBackend(provider: .modal, credentials: credentials)

        #expect(await backend.isAvailable())
        await #expect(throws: BackendError.self) {
            try await backend.wake()
        }
    }

    @Test func isConfiguredNeverExposesTheSecretValue() {
        // isConfigured returns a Bool — there is no code path by which the
        // token value itself could leak through this API.
        let credentials = CloudCredentialsStore(secrets: InMemorySecretStore())
        credentials.setCredential("super-secret-token", for: .daytona)
        let configured = credentials.isConfigured(.daytona)
        #expect(configured == true)
        // isConfigured's return type is Bool; nothing to assert beyond the
        // fact that the token string never appears in `configured`.
        #expect("\(configured)" == "true")
    }
}
