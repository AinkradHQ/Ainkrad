// Sources/Ainkrad/Core/AgentKit/Autonomy/AgentSessionSubagentRunner.swift
import Foundation

/// The production `SubagentRunner`: resolves an `AgentProfile`, asks the Model
/// Router for a concrete model within the spec's budget ceiling, narrows the
/// tool surface via `SubagentRegistryFilter`, spins a child `AgentSession`
/// (via the injected `makeSession` seam), runs the prompt, and maps the final
/// session state to a `SubagentOutcome`.
///
/// Failure isolation: `run` never throws — a child session that settles into
/// `.failed` maps to a `.failed` outcome rather than propagating.
@MainActor
final class AgentSessionSubagentRunner: SubagentRunner {
    private let allTools: [any AgentTool]
    private let agents: AgentStore
    private let router: ModelRouter
    /// M7 Slice 3b Task 21 — resolves the `SandboxProfile` every child session's
    /// tools are narrowed to. Every subagent runs at trust tier `.subagent`
    /// (never `.mainInteractive`), so this always resolves to a sandboxed
    /// (never `.host`) profile — see `ExecutionRouter.resolveProfile`.
    private let executionRouter: ExecutionRouter
    private let candidatesProvider: @MainActor () -> [RouterCandidate]
    private let makeSession: @MainActor (AgentProfile, AgentToolRegistry, String, Set<String>) -> AgentSession

    init(
        allTools: [any AgentTool], agents: AgentStore, router: ModelRouter,
        executionRouter: ExecutionRouter,
        candidatesProvider: @escaping @MainActor () -> [RouterCandidate],
        makeSession: @escaping @MainActor (AgentProfile, AgentToolRegistry, String, Set<String>) -> AgentSession
    ) {
        self.allTools = allTools
        self.agents = agents
        self.router = router
        self.executionRouter = executionRouter
        self.candidatesProvider = candidatesProvider
        self.makeSession = makeSession
    }

    func run(_ spec: SubagentSpec) async -> SubagentOutcome {
        let profile = spec.profileID.flatMap { id in agents.agents.first { $0.id == id } } ?? agents.active

        let decision = router.route(
            forSubagent: SubagentModelRequest(
                budgetTier: spec.budgetTier, needsVision: false, needsTools: true,
                estimatedInputTokens: max(1, spec.prompt.count / 4),
                candidates: candidatesProvider()))

        let tools = SubagentRegistryFilter.tools(from: allTools, allow: spec.toolAllowList, policy: profile.toolPolicy)
        let registry = AgentToolRegistry(tools: tools)
        // `AgentProfile` carries no per-Agent `AgentExecutionPolicy` projection yet
        // (no `sandboxProfileID`/`allowCloud` fields) — `policy: nil` lets the
        // router fall back to `.subagent`'s restrictive tier default
        // (`BuiltInSandboxProfiles.workspaceWrite`), which is fail-closed, never
        // an escalation. See Task 21 report for this discrepancy vs. the brief.
        let sandboxProfile = executionRouter.resolveProfile(tier: .subagent, policy: nil)
        let session = makeSession(profile, registry, decision.candidate.model, sandboxProfile.toolAllowList)

        session.send(spec.prompt)
        await session.currentTask?.value

        if case .failed(let message) = session.state {
            return SubagentOutcome(id: spec.id, status: .failed, resultText: message)
        }
        let text = session.messages.last { $0.role == .assistant }?.text ?? ""
        return SubagentOutcome(id: spec.id, status: .succeeded, resultText: text)
    }
}
