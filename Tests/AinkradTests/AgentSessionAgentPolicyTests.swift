import AinkradHostRuntime
// Tests/AinkradTests/AgentSessionAgentPolicyTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("AgentSession agent policy")
@MainActor
struct AgentSessionAgentPolicyTests {
    @Test func planAgentBlocksWriteToolBeforeGate() async throws {
        let agents = AgentStore(persistence: InMemoryPersistenceStore())
        agents.setActive(BuiltInAgents.planID)
        let session = TestSessionFactory.make(agents: agents)
        let result = await session.executeForTesting(
            ToolCall(id: "1", name: "edit_file", input: .object(["path": .string("/tmp/x")])))
        #expect(result.isError)
        #expect(result.content.contains("not permitted"))
    }

    @Test func buildAgentAllowsWriteToolThroughToGate() async throws {
        let agents = AgentStore(persistence: InMemoryPersistenceStore())
        agents.setActive(BuiltInAgents.buildID)
        let session = TestSessionFactory.make(agents: agents)
        // Build permits the tool; it is then visible in the schemas presented
        // to the provider (rather than being filtered out pre-gate like Plan).
        let schemas = session.allowedSchemasForTesting()
        #expect(schemas.contains { $0.name == "edit_file" })
    }

    @Test func planAgentSchemasExcludeWriteTool() async throws {
        let agents = AgentStore(persistence: InMemoryPersistenceStore())
        agents.setActive(BuiltInAgents.planID)
        let session = TestSessionFactory.make(agents: agents)
        // edit_file is present in the full registry (see buildAgentAllowsWriteToolThroughToGate),
        // so a non-empty absence here proves filtering, not an empty registry.
        let schemas = session.allowedSchemasForTesting()
        #expect(!schemas.contains { $0.name == "edit_file" })
    }

    @Test func postureComposesMostRestrictiveWins() {
        // Workspace fullAuto + a custom agent with posture .ask → effective .ask.
        let agents = AgentStore(persistence: InMemoryPersistenceStore())
        var reviewer = AgentProfile.custom(name: "Reviewer", instructions: "x")
        reviewer.permissionPosture = .ask
        agents.setActive(agents.add(reviewer).id)
        let session = TestSessionFactory.make(agents: agents, mode: .fullAuto)
        #expect(session.effectiveModeForTesting() == .ask)
    }

    // M7 Wave B (B1) — a schedule/trigger's own `SavedExecutionPosture`,
    // projected into `AgentSession` as `permissionModeOverride`, composes into
    // `effectiveMode()` the SAME most-restrictive-wins way as the Agent's own
    // `permissionPosture` above.
    @Test func scheduledRunPostureNarrowsBelowGlobalMode() {
        // Workspace fullAuto + a schedule posture override of .ask → effective
        // .ask, NOT the global fullAuto: this is the run whose posture actually
        // narrows, proven against the global mode it would otherwise inherit.
        let session = TestSessionFactory.make(mode: .fullAuto, permissionModeOverride: .ask)
        #expect(session.effectiveModeForTesting() == .ask)
    }

    @Test func scheduledRunPostureCannotWidenBeyondGlobalMode() {
        // Security invariant: a posture override can only NARROW, never widen.
        // Workspace .ask + a (hypothetical, malformed) override of .fullAuto
        // must still settle to .ask — the more restrictive of the two wins,
        // exactly mirroring the Agent-profile posture seam's own guarantee.
        let session = TestSessionFactory.make(mode: .ask, permissionModeOverride: .fullAuto)
        #expect(session.effectiveModeForTesting() == .ask)
    }
}
