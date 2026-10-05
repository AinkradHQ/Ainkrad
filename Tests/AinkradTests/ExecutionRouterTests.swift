import AinkradHostRuntime
// Tests/AinkradTests/ExecutionRouterTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("ExecutionRouter")
@MainActor
struct ExecutionRouterTests {
    // A stub backend that reports a fixed availability + records runs.
    struct StubBackend: ExecutionBackend {
        let kind: SandboxBackendKind
        let available: Bool
        func isAvailable() async -> Bool { available }
        func run(_ request: ExecutionRequest) async throws -> ExecutionResult {
            ExecutionResult(output: "\(kind)", exitCode: 0, timedOut: false, unresponsive: false)
        }
    }

    private func router(
        available: Bool = true,
        overrides: [SandboxBackendKind: any ExecutionBackend] = [:]
    ) -> ExecutionRouter {
        var backends: [SandboxBackendKind: any ExecutionBackend] = [
            .host: StubBackend(kind: .host, available: true),
            .seatbelt: StubBackend(kind: .seatbelt, available: available),
            .docker: StubBackend(kind: .docker, available: available),
            .ssh: StubBackend(kind: .ssh, available: available),
            .cloud: StubBackend(kind: .cloud, available: available),
        ]
        for (k, v) in overrides { backends[k] = v }
        return ExecutionRouter(
            profiles: SandboxProfileStore(persistence: InMemoryPersistenceStore()),
            backends: backends)
    }

    @Test func mainInteractiveUsesHost() async throws {
        let (backend, profile) = try await router().route(tier: .mainInteractive, policy: nil)
        #expect(backend.kind == .host)
        #expect(profile.id == BuiltInSandboxProfiles.mainID)
    }

    @Test func backgroundDefaultsToWorkspaceWriteSeatbelt() async throws {
        let (backend, profile) = try await router().route(tier: .background, policy: nil)
        #expect(backend.kind == .seatbelt)
        #expect(profile.id == BuiltInSandboxProfiles.defaultNonMainID)
    }

    @Test func scheduledDefaultsToWorkspaceWriteSeatbelt() async throws {
        let (backend, profile) = try await router().route(tier: .scheduled, policy: nil)
        #expect(backend.kind == .seatbelt)
        #expect(profile.id == BuiltInSandboxProfiles.defaultNonMainID)
    }

    @Test func subagentDefaultsToWorkspaceWriteSeatbelt() async throws {
        let (backend, profile) = try await router().route(tier: .subagent, policy: nil)
        #expect(backend.kind == .seatbelt)
        #expect(profile.id == BuiltInSandboxProfiles.defaultNonMainID)
    }

    @Test func untrustedMCPDefaultsToWorkspaceWriteSeatbelt() async throws {
        let (backend, profile) = try await router().route(tier: .untrustedMCP, policy: nil)
        #expect(backend.kind == .seatbelt)
        #expect(profile.id == BuiltInSandboxProfiles.defaultNonMainID)
    }

    @Test func nonMainCannotSilentlyEscalateToHost() async throws {
        // A policy naming the host-trusted profile (backend .host) for a subagent
        // tier must NOT run on host — allowHostOverride guards it.
        let policy = AgentExecutionPolicy(
            sandboxProfileID: BuiltInSandboxProfiles.mainID,
            allowCloud: false, toolAllowList: nil)
        let (backend, profile) = try await router().route(tier: .subagent, policy: policy)
        #expect(backend.kind == .seatbelt)  // fell back, not host
        #expect(profile.id == BuiltInSandboxProfiles.defaultNonMainID)
    }

    @Test func backgroundCannotSilentlyEscalateToHost() async throws {
        let policy = AgentExecutionPolicy(
            sandboxProfileID: BuiltInSandboxProfiles.mainID,
            allowCloud: false, toolAllowList: nil)
        let (backend, profile) = try await router().route(tier: .background, policy: policy)
        #expect(backend.kind == .seatbelt)
        #expect(profile.id == BuiltInSandboxProfiles.defaultNonMainID)
    }

    @Test func unavailableBackendFailsClosed() async {
        let r = router(available: false)
        await #expect(throws: ExecutionRouterError.self) {
            _ = try await r.route(tier: .background, policy: nil)
        }
    }

    @Test func unavailableDockerForNonMainDoesNotFallBackToHost() async {
        // A policy naming an unavailable docker profile for a non-main tier must
        // throw — NEVER substitute host.
        let dockerProfile = SandboxProfile(
            id: "docker-p", name: "Docker", backend: .docker,
            fsPolicy: FilesystemPolicy(readablePaths: ["<workspace>"], writablePaths: ["<workspace>"]),
            networkPolicy: .off, resourceLimits: ResourceLimits(timeoutSeconds: 60), toolAllowList: [])
        let store = SandboxProfileStore(persistence: InMemoryPersistenceStore())
        store.upsert(dockerProfile)
        let r = ExecutionRouter(
            profiles: store,
            backends: [
                .host: StubBackend(kind: .host, available: true),
                .docker: StubBackend(kind: .docker, available: false),
            ])
        await #expect(throws: ExecutionRouterError.self) {
            _ = try await r.route(
                tier: .background,
                policy: AgentExecutionPolicy(sandboxProfileID: "docker-p", allowCloud: false, toolAllowList: nil))
        }
    }

    @Test func unknownProfileIDFallsBackToRestrictiveDefault() async throws {
        // A policy naming a profile id that doesn't exist must never crash or
        // escalate — it falls back to the restrictive default for the tier.
        let policy = AgentExecutionPolicy(
            sandboxProfileID: "does-not-exist",
            allowCloud: false, toolAllowList: nil)
        let (backend, profile) = try await router().route(tier: .background, policy: policy)
        #expect(backend.kind == .seatbelt)
        #expect(profile.id == BuiltInSandboxProfiles.defaultNonMainID)
    }

    @Test func cloudRequiresOptIn() async throws {
        let cloudProfile = SandboxProfile(
            id: "cloud-p", name: "Cloud", backend: .cloud,
            fsPolicy: FilesystemPolicy(readablePaths: [], writablePaths: []),
            networkPolicy: .on, resourceLimits: ResourceLimits(timeoutSeconds: 60), toolAllowList: [])
        let store = SandboxProfileStore(persistence: InMemoryPersistenceStore())
        store.upsert(cloudProfile)
        let r = ExecutionRouter(
            profiles: store,
            backends: [
                .seatbelt: StubBackend(kind: .seatbelt, available: true),
                .cloud: StubBackend(kind: .cloud, available: true),
            ])
        // allowCloud false → error
        await #expect(throws: ExecutionRouterError.self) {
            _ = try await r.route(
                tier: .background,
                policy: AgentExecutionPolicy(sandboxProfileID: "cloud-p", allowCloud: false, toolAllowList: nil))
        }
        // allowCloud true → routes to cloud
        let (backend, _) = try await r.route(
            tier: .background,
            policy: AgentExecutionPolicy(sandboxProfileID: "cloud-p", allowCloud: true, toolAllowList: nil))
        #expect(backend.kind == .cloud)
    }

    @Test func cloudNeverSelectedByTierAloneWithNilPolicy() async throws {
        // No policy at all → tier alone must never yield cloud, even if somehow
        // a tier's resolved default were cloud (it never is by construction).
        let (backend, _) = try await router().route(tier: .background, policy: nil)
        #expect(backend.kind != .cloud)
    }

    @Test func backgroundPostureCannotNameABroaderSandboxedProfile() async throws {
        // A posture naming `networked-build` (network `.on`, strictly broader
        // than `workspace-write`'s network `.off`) for a `.background` run
        // must be narrowed back to the tier's restrictive default — the
        // ceiling never lets a posture widen a background run beyond it.
        let store = SandboxProfileStore(persistence: InMemoryPersistenceStore())
        store.upsert(BuiltInSandboxProfiles.networkedBuild)
        let r = ExecutionRouter(
            profiles: store,
            backends: [
                .seatbelt: StubBackend(kind: .seatbelt, available: true)
            ])
        let policy = AgentExecutionPolicy(
            sandboxProfileID: BuiltInSandboxProfiles.networkedBuild.id,
            allowCloud: false, toolAllowList: nil)
        let (backend, profile) = try await r.route(tier: .background, policy: policy)
        #expect(backend.kind == .seatbelt)
        #expect(profile.id == BuiltInSandboxProfiles.defaultNonMainID)
    }

    @Test func backgroundPostureNamingAnNarrowerSandboxedProfileIsHonored() async throws {
        // A posture naming `read-only` (strictly narrower than the default
        // `workspace-write`: no writable paths at all) must still be honored
        // — the ceiling only blocks widening, never narrowing.
        let store = SandboxProfileStore(persistence: InMemoryPersistenceStore())
        store.upsert(BuiltInSandboxProfiles.readOnly)
        let r = ExecutionRouter(
            profiles: store,
            backends: [
                .seatbelt: StubBackend(kind: .seatbelt, available: true)
            ])
        let policy = AgentExecutionPolicy(
            sandboxProfileID: BuiltInSandboxProfiles.readOnly.id,
            allowCloud: false, toolAllowList: nil)
        let (backend, profile) = try await r.route(tier: .background, policy: policy)
        #expect(backend.kind == .seatbelt)
        #expect(profile.id == BuiltInSandboxProfiles.readOnly.id)
    }
}
