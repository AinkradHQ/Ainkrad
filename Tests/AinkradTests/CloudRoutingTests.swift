import AinkradHostRuntime
// Tests/AinkradTests/CloudRoutingTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("Cloud routing")
@MainActor
struct CloudRoutingTests {
    @Test func cloudProfileBlockedWithoutPerAgentOptIn() async {
        let creds = CloudCredentialsStore(secrets: InMemorySecretStore())
        creds.setCredential("tok", for: .modal)
        let store = SandboxProfileStore(persistence: InMemoryPersistenceStore())
        store.upsert(
            SandboxProfile(
                id: "cloud-p", name: "Cloud", backend: .cloud,
                fsPolicy: FilesystemPolicy(readablePaths: [], writablePaths: []),
                networkPolicy: .on, resourceLimits: ResourceLimits(timeoutSeconds: 60), toolAllowList: []))
        let router = ExecutionRouter(
            profiles: store,
            backends: [
                .seatbelt: SeatbeltBackend(),
                .cloud: ModalCloudBackend(credentials: creds),
            ])
        // No per-Agent opt-in → cloudNotOptedIn, even though creds exist.
        await #expect(throws: ExecutionRouterError.self) {
            _ = try await router.route(
                tier: .background,
                policy: AgentExecutionPolicy(sandboxProfileID: "cloud-p", allowCloud: false, toolAllowList: nil))
        }
    }

    @Test func cloudOptInPlusConfiguredCredsRoutesToModalBackendWhichFailsClosedOnExec() async throws {
        let creds = CloudCredentialsStore(secrets: InMemorySecretStore())
        creds.setCredential("tok", for: .modal)
        let store = SandboxProfileStore(persistence: InMemoryPersistenceStore())
        store.upsert(
            SandboxProfile(
                id: "cloud-p", name: "Cloud", backend: .cloud,
                fsPolicy: FilesystemPolicy(readablePaths: [], writablePaths: []),
                networkPolicy: .on, resourceLimits: ResourceLimits(timeoutSeconds: 60), toolAllowList: []))
        let modal = ModalCloudBackend(credentials: creds)
        let router = ExecutionRouter(
            profiles: store,
            backends: [
                .seatbelt: SeatbeltBackend(),
                .cloud: modal,
            ])

        let (backend, profile) = try await router.route(
            tier: .background,
            policy: AgentExecutionPolicy(sandboxProfileID: "cloud-p", allowCloud: true, toolAllowList: nil))
        #expect(backend.kind == .cloud)
        #expect(profile.id == "cloud-p")

        // Even opted-in + configured, real remote execution still fails closed
        // (the Modal remote-exec driver is a research stub) — never a false
        // "cloud works" path, never a local fallback.
        await #expect(throws: (any Error).self) {
            _ = try await backend.run(ExecutionRequest(command: "echo hi", workingDir: "/tmp", profile: profile))
        }
    }

    @Test func defaultNilPolicyNeverRoutesToCloud() async throws {
        let creds = CloudCredentialsStore(secrets: InMemorySecretStore())
        creds.setCredential("tok", for: .modal)
        let store = SandboxProfileStore(persistence: InMemoryPersistenceStore())
        let router = ExecutionRouter(
            profiles: store,
            backends: [
                .seatbelt: SeatbeltBackend(),
                .cloud: ModalCloudBackend(credentials: creds),
            ])
        // No policy at all (nil) → falls back to the tier's restrictive
        // default, never cloud, regardless of configured credentials.
        let (backend, _) = try await router.route(tier: .background, policy: nil)
        #expect(backend.kind != .cloud)
    }
}
