import AinkradHostRuntime
// Tests/AinkradTests/AgentSessionSubagentRunnerTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("AgentSessionSubagentRunner")
@MainActor
struct AgentSessionSubagentRunnerTests {
    private func candidates() -> [RouterCandidate] {
        [
            RouterCandidate(
                connectionID: UUID(), model: "llama3.2",
                descriptor: ModelDescriptor(
                    id: "llama3.2", tier: .local, contextWindow: 128_000,
                    capabilities: [.toolUse], matchPrefixes: ["llama"])),
            RouterCandidate(
                connectionID: UUID(), model: "claude-opus-4-8",
                descriptor: ModelDescriptor(
                    id: "claude-opus-4-8", tier: .premium, contextWindow: 200_000,
                    capabilities: [.toolUse], matchPrefixes: ["claude"])),
        ]
    }

    @Test func routesWithinBudgetAndReturnsResult() async {
        let agents = AgentStore(persistence: InMemoryPersistenceStore())
        let router = ModelRouter(
            catalog: ModelCatalog(),
            outcomes: RouterOutcomeStore(persistence: InMemoryPersistenceStore()))
        var chosenModel: String?
        let executionRouter = ExecutionRouter(
            profiles: SandboxProfileStore(persistence: InMemoryPersistenceStore()), backends: [:])
        let runner = AgentSessionSubagentRunner(
            allTools: [ReadFileTool(), EditFileTool()],
            agents: agents, router: router, executionRouter: executionRouter,
            candidatesProvider: candidates,
            makeSession: { _, registry, model, _ in
                chosenModel = model
                return StubChildSession.make(finalText: "did:\(registry.schemas.count) tools on \(model)")
            })
        let out = await runner.run(
            SubagentSpec(prompt: "scan the repo", toolAllowList: ["read_file"], budgetTier: .cheapPaid))
        #expect(out.status == .succeeded)
        #expect(chosenModel == "llama3.2")  // budget ceiling honored (local ≤ cheapPaid, free-first)
        #expect(out.resultText.contains("did:1 tools"))  // allow-list narrowed to read_file
    }

    @Test func failedChildStateMapsToFailedOutcomeWithoutThrowing() async {
        let agents = AgentStore(persistence: InMemoryPersistenceStore())
        let router = ModelRouter(
            catalog: ModelCatalog(),
            outcomes: RouterOutcomeStore(persistence: InMemoryPersistenceStore()))
        let executionRouter = ExecutionRouter(
            profiles: SandboxProfileStore(persistence: InMemoryPersistenceStore()), backends: [:])
        let runner = AgentSessionSubagentRunner(
            allTools: [ReadFileTool(), EditFileTool()],
            agents: agents, router: router, executionRouter: executionRouter,
            candidatesProvider: candidates,
            makeSession: { _, _, _, _ in FailingChildSession.make() })
        let out = await runner.run(SubagentSpec(prompt: "do it", toolAllowList: [], budgetTier: .premium))
        #expect(out.status == .failed)
        #expect(!out.resultText.isEmpty)
    }
}
