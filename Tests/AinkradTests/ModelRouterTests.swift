import AinkradHostRuntime
// Tests/AinkradTests/ModelRouterTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("ModelRouter")
@MainActor
struct ModelRouterTests {
    private func cand(_ id: String, _ tier: ModelTier, _ ctx: Int, _ caps: ModelCapability) -> RouterCandidate {
        RouterCandidate(
            connectionID: UUID(), model: id,
            descriptor: ModelDescriptor(id: id, tier: tier, contextWindow: ctx, capabilities: caps))
    }
    private func router(_ policy: RouterPolicy = .saveMoney) -> ModelRouter {
        ModelRouter(
            catalog: ModelCatalog(), policy: policy,
            outcomes: RouterOutcomeStore(persistence: InMemoryPersistenceStore()))
    }

    @Test func userPinWinsOverEverything() async {
        let r = router()
        let d = await r.route(
            RouterRequest(
                signal: TaskSignal(
                    estimatedInputTokens: 100, needsVision: false, needsTools: false, reasoningHeavy: false),
                lastMessage: "hi",
                routing: AgentRouting(),
                candidates: [cand("local", .local, 128_000, [.toolUse]), cand("opus", .premium, 200_000, [.toolUse])],
                userPinnedModel: "opus", attempt: 0))
        #expect(d.candidate.model == "opus")
        #expect(d.reason.contains("pinned"))
    }

    @Test func trivialTaskPicksLocalFirst() async {
        let r = router()
        let d = await r.route(
            RouterRequest(
                signal: TaskSignal(
                    estimatedInputTokens: 50, needsVision: false, needsTools: false, reasoningHeavy: false),
                lastMessage: "hi",
                routing: AgentRouting(),
                candidates: [cand("opus", .premium, 200_000, [.toolUse]), cand("local", .local, 128_000, [.toolUse])],
                userPinnedModel: nil, attempt: 0))
        #expect(d.candidate.model == "local")
        #expect(d.baselineModel == "opus")  // savings baseline recorded
    }

    @Test func escalationRaisesTierOnRetry() async {
        let r = router()
        let base = RouterRequest(
            signal: TaskSignal(estimatedInputTokens: 50, needsVision: false, needsTools: true, reasoningHeavy: false),
            lastMessage: "do a thing",
            routing: AgentRouting(),
            candidates: [
                cand("local", .local, 128_000, [.toolUse]), cand("mini", .cheapPaid, 400_000, [.toolUse]),
                cand("opus", .premium, 200_000, [.toolUse]),
            ],
            userPinnedModel: nil, attempt: 2)
        let d = await r.route(base)
        #expect(d.escalated)
        #expect(d.candidate.descriptor.tier >= .cheapPaid)
    }

    @Test func maxTierBoundRespected() async {
        let r = router()
        let d = await r.route(
            RouterRequest(
                signal: TaskSignal(
                    estimatedInputTokens: 50, needsVision: false, needsTools: true, reasoningHeavy: true),
                lastMessage: "prove correctness and refactor",
                routing: AgentRouting(maxTier: .cheapPaid),
                candidates: [
                    cand("mini", .cheapPaid, 400_000, [.toolUse]), cand("opus", .premium, 200_000, [.toolUse]),
                ],
                userPinnedModel: nil, attempt: 0))
        #expect(d.candidate.descriptor.tier <= .cheapPaid)  // never exceeds ceiling even for a hard task
    }

    @Test func maxTierBoundRespectedEvenUnderEscalation() async {
        // Same as above but with attempt > 0 so escalation kicks in too — the ceiling
        // must win over BOTH the difficulty floor and the escalation bump.
        let r = router()
        let d = await r.route(
            RouterRequest(
                signal: TaskSignal(
                    estimatedInputTokens: 50, needsVision: false, needsTools: true, reasoningHeavy: true),
                lastMessage: "prove correctness and refactor",
                routing: AgentRouting(maxTier: .cheapPaid),
                candidates: [
                    cand("mini", .cheapPaid, 400_000, [.toolUse]), cand("opus", .premium, 200_000, [.toolUse]),
                ],
                userPinnedModel: nil, attempt: 3))
        #expect(d.candidate.descriptor.tier <= .cheapPaid)
        #expect(d.candidate.model == "mini")
    }

    @Test func subagentBudgetIsCeiling() {
        let r = router()
        let d = r.route(
            forSubagent: SubagentModelRequest(
                budgetTier: .cheapPaid, needsVision: false, needsTools: true, estimatedInputTokens: 100,
                candidates: [cand("local", .local, 128_000, [.toolUse]), cand("opus", .premium, 200_000, [.toolUse])]))
        #expect(d.candidate.descriptor.tier <= .cheapPaid)
    }

    @Test func capabilityFilterIsHardOnTheAutoPath() async {
        // A vision-requiring signal cannot be routed to a text-only candidate on the auto
        // (unpinned) path — the facade must never fabricate a bypass.
        let r = router()
        let d = await r.route(
            RouterRequest(
                signal: TaskSignal(
                    estimatedInputTokens: 50, needsVision: true, needsTools: false, reasoningHeavy: false),
                lastMessage: "what's in this image",
                routing: AgentRouting(),
                candidates: [cand("local", .local, 128_000, [.toolUse])],  // no vision capability anywhere
                userPinnedModel: nil, attempt: 0))
        #expect(d.reason.contains("no capable model") || d.reason.contains("No capable model"))
        #expect(!d.pinnedButIncapable)
    }

    @Test func pinnedModelIncapableOfVisionIsHonoredButFlagged() async {
        // A user pin still wins outright even when the pinned model lacks a capability the
        // task requires (here: vision) — but the router must surface that incapability via
        // `pinnedButIncapable` so callers (session wiring / UI) can warn the user instead of
        // silently sending a model that can't do the job.
        let r = router()
        let d = await r.route(
            RouterRequest(
                signal: TaskSignal(
                    estimatedInputTokens: 50, needsVision: true, needsTools: false, reasoningHeavy: false),
                lastMessage: "what's in this image",
                routing: AgentRouting(),
                candidates: [cand("local", .local, 128_000, [.toolUse])],  // no vision capability anywhere
                userPinnedModel: "local", attempt: 0))
        #expect(d.candidate.model == "local")  // pin still wins
        #expect(d.pinnedButIncapable)
    }

    @Test func pinnedModelCapableIsNotFlagged() async {
        // Sanity check: a pinned model that DOES satisfy the task's capabilities is not
        // flagged incapable.
        let r = router()
        let d = await r.route(
            RouterRequest(
                signal: TaskSignal(
                    estimatedInputTokens: 50, needsVision: true, needsTools: false, reasoningHeavy: false),
                lastMessage: "what's in this image",
                routing: AgentRouting(),
                candidates: [cand("vision-model", .local, 128_000, [.vision])],
                userPinnedModel: "vision-model", attempt: 0))
        #expect(d.candidate.model == "vision-model")
        #expect(!d.pinnedButIncapable)
    }

    @Test func routerDisabledReturnsDefaultNotAutoPicked() async {
        // routerEnabled == false must bypass free-first/escalation entirely and hand back
        // a default (the first candidate given), not whatever the auto-picker would choose.
        let r = router()
        let d = await r.route(
            RouterRequest(
                signal: TaskSignal(
                    estimatedInputTokens: 50, needsVision: false, needsTools: false, reasoningHeavy: false),
                lastMessage: "hi",
                routing: AgentRouting(routerEnabled: false),
                candidates: [cand("opus", .premium, 200_000, [.toolUse]), cand("local", .local, 128_000, [.toolUse])],
                userPinnedModel: nil, attempt: 0))
        #expect(d.candidate.model == "opus")  // first candidate = default, not the free-first "local"
        #expect(!d.escalated)
    }

    @Test func routerDisabledStillHonorsUserPin() async {
        let r = router()
        let d = await r.route(
            RouterRequest(
                signal: TaskSignal(
                    estimatedInputTokens: 50, needsVision: false, needsTools: false, reasoningHeavy: false),
                lastMessage: "hi",
                routing: AgentRouting(routerEnabled: false),
                candidates: [cand("opus", .premium, 200_000, [.toolUse]), cand("local", .local, 128_000, [.toolUse])],
                userPinnedModel: "local", attempt: 0))
        #expect(d.candidate.model == "local")
    }

    @Test func emptyCandidatesYieldsSyntheticNoCapableDecision() async {
        let r = router()
        let d = await r.route(
            RouterRequest(
                signal: TaskSignal(
                    estimatedInputTokens: 50, needsVision: false, needsTools: false, reasoningHeavy: false),
                lastMessage: "hi",
                routing: AgentRouting(),
                candidates: [],
                userPinnedModel: nil, attempt: 0))
        #expect(d.reason == "no capable model")
        #expect(d.candidate.model == "none")
    }

    @Test func recordOutcomeAndOverrideForwardToStore() async {
        let outcomes = RouterOutcomeStore(persistence: InMemoryPersistenceStore())
        let r = ModelRouter(catalog: ModelCatalog(), policy: .saveMoney, outcomes: outcomes)
        let d = await r.route(
            RouterRequest(
                signal: TaskSignal(
                    estimatedInputTokens: 50, needsVision: false, needsTools: false, reasoningHeavy: false),
                lastMessage: "hi",
                routing: AgentRouting(),
                candidates: [cand("local", .local, 128_000, [.toolUse])],
                userPinnedModel: nil, attempt: 0))
        r.recordOutcome(d, success: true)
        r.recordOverride(d)
        #expect(outcomes.successRate(difficulty: .trivial, model: "local") == 1.0)
    }
}
