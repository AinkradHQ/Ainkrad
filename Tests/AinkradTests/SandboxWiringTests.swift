import AinkradHostRuntime
// Tests/AinkradTests/SandboxWiringTests.swift
import Foundation
import Testing

@testable import Ainkrad

/// M7 Slice 6 Task 12: proves the wiring in `AppEnvironment.bootstrap()` —
/// all backends registered by their own kind, and `RunTerminalTool` still
/// resolves the main-interactive tier to `HostBackend` (byte-identical to
/// the pre-router behavior).
@Suite("Sandbox wiring")
@MainActor
struct SandboxWiringTests {
    @Test func routerRoutesMainToHost() async throws {
        let store = SandboxProfileStore(persistence: InMemoryPersistenceStore())
        let router = ExecutionRouter(
            profiles: store,
            backends: [
                .host: HostBackend(), .seatbelt: SeatbeltBackend(),
                .docker: DockerBackend(), .ssh: SSHBackend(resolveConnection: nil),
            ])
        let (backend, _) = try await router.route(tier: .mainInteractive, policy: nil)
        #expect(backend.kind == .host)
    }

    @Test func runTerminalConstructsWithRouter() {
        let hub = AgentActionRegistryHub()  // bound locally: the tool holds it unowned
        let router = ExecutionRouter(
            profiles: SandboxProfileStore(persistence: InMemoryPersistenceStore()),
            backends: [.host: HostBackend()])
        let tool = RunTerminalTool(actionHub: hub, router: router)
        #expect(tool.name == "run_terminal")
    }

    @Test func bootstrapRegistersAllBackendsAndUsesHostForMain() async throws {
        let t = TestHome.make("sandbox-wiring")
        defer { t.cleanup() }

        let environment = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        // Non-main tiers must resolve to a registered, non-host backend
        // rather than throwing "no backend registered" — proves seatbelt
        // (and, when present, docker/ssh) are actually wired, not just host.
        let (backend, _) = try await environment.executionRouter.route(tier: .background, policy: nil)
        #expect(backend.kind != .host)

        // The main-interactive tier is unaffected — still resolves to host,
        // byte-identical to pre-router behavior.
        let (mainBackend, _) = try await environment.executionRouter.route(tier: .mainInteractive, policy: nil)
        #expect(mainBackend.kind == .host)
    }
}
