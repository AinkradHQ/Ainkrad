// Sources/Ainkrad/Core/AgentKit/Router/ModelRouter.swift
import Foundation

/// One turn's routing request: everything `ModelRouter.route` needs to pick a model.
struct RouterRequest: Sendable {
    let signal: TaskSignal
    let lastMessage: String
    let routing: AgentRouting
    let candidates: [RouterCandidate]
    let userPinnedModel: String?
    let attempt: Int
}

/// The router's output for a turn: the picked candidate, the reasoning surfaced to the
/// transcript, whether this was an escalation, and the premium `baselineModel` a free-first
/// pick avoided (feeds `UsageTracker` savings accounting).
struct RouterDecision: Equatable, Sendable {
    let candidate: RouterCandidate
    let tier: ModelTier
    let reason: String
    let escalated: Bool
    let baselineModel: String?
    /// True when a user pin (or Agent default, honored via the "router disabled" path) was
    /// returned even though its `ModelDescriptor` fails the task's capability/context-window
    /// check (the same `RouterOrdering.capable` predicate the auto path enforces). The pin
    /// still wins — this only makes the incapability visible to callers (session wiring, UI)
    /// so they can warn the user instead of silently sending an incapable model. Always
    /// `false` outside the pin/disabled-router paths.
    var pinnedButIncapable: Bool = false
}

/// A subagent spawn request: a budget/class from `spawn_subagent`, resolved to a concrete
/// model synchronously (no async classifier — subagents are rule-only).
struct SubagentModelRequest: Sendable {
    let budgetTier: ModelTier
    let needsVision: Bool
    let needsTools: Bool
    let estimatedInputTokens: Int
    let candidates: [RouterCandidate]
}

/// The Model Router facade — the single entry point that ties `ModelCatalog`,
/// `RouterPolicy`/`RouterOrdering`, `DifficultyClassifier`, and `RouterOutcomeStore`
/// together to pick a concrete model for a turn (`route`) or a subagent
/// (`route(forSubagent:)`).
///
/// Every dependency degradation (no classifier, empty outcome history, unknown price)
/// still yields a valid `RouterDecision` — this facade never hangs, throws, or returns nil.
@MainActor
final class ModelRouter {
    private let catalog: ModelCatalog
    var policy: RouterPolicy
    private let outcomes: RouterOutcomeStore
    private let classify: (@Sendable (String) async -> ClassifierResult?)?
    private let confidenceThreshold = 0.5
    private let maxEscalationAttempts = 3

    init(
        catalog: ModelCatalog, policy: RouterPolicy = .saveMoney,
        outcomes: RouterOutcomeStore,
        classify: (@Sendable (String) async -> ClassifierResult?)? = nil
    ) {
        self.catalog = catalog
        self.policy = policy
        self.outcomes = outcomes
        self.classify = classify
    }

    /// Pipeline: user pin (or a disabled router) wins outright → else capability-filter →
    /// bound by the Agent's routing envelope → order (free-first + preferred + learned) →
    /// apply the difficulty's minimum-tier floor + attempt-based escalation, both still
    /// clipped to the Agent's bounds → pick the head.
    func route(_ request: RouterRequest) async -> RouterDecision {
        // 1. User pin wins over everything, including a disabled router.
        if let pinned = request.userPinnedModel,
            let match = request.candidates.first(where: { $0.model == pinned })
        {
            // Reuse the SAME hard capability check the auto path enforces (Task 10's
            // `RouterOrdering.capable`) — the pin still wins even if it fails, but we
            // surface that failure instead of hiding it.
            let incapable = RouterOrdering.capable([match], for: request.signal).isEmpty
            return RouterDecision(
                candidate: match, tier: match.descriptor.tier,
                reason: "User pinned \(pinned).", escalated: false, baselineModel: nil,
                pinnedButIncapable: incapable)
        }

        // 2. Router disabled (and no pin matched above): use the caller-supplied default —
        //    the first candidate — never the auto-picker's choice.
        if !request.routing.routerEnabled {
            let fallback = request.candidates.first ?? Self.synthetic()
            return RouterDecision(
                candidate: fallback, tier: fallback.descriptor.tier,
                reason: "Router disabled; using default model \(fallback.model).",
                escalated: false, baselineModel: nil)
        }

        guard !request.candidates.isEmpty else {
            let fallback = Self.synthetic()
            return RouterDecision(
                candidate: fallback, tier: fallback.descriptor.tier,
                reason: "no capable model", escalated: false, baselineModel: nil)
        }

        // 3. Capability + bounds (both hard filters — never bypassed).
        let capable = RouterOrdering.capable(request.candidates, for: request.signal)
        let bounded = RouterOrdering.bounded(capable, by: request.routing)
        guard !bounded.isEmpty else {
            let fallback = request.candidates.first ?? Self.synthetic()
            return RouterDecision(
                candidate: fallback, tier: fallback.descriptor.tier,
                reason: "No capable model within bounds.", escalated: false, baselineModel: nil)
        }

        // 4. Difficulty (rules, optionally refined by the cheap classifier — never blocks).
        var result = DifficultyClassifier.ruleScore(request.signal, lastMessage: request.lastMessage)
        if let classify, let refined = await classify(request.lastMessage) { result = refined }

        // 5. Floor tier from difficulty + escalation on retry, both clipped by `bounded`
        //    (which already excludes anything past the Agent's `maxTier`/`allowedModels`)
        //    so escalation can never break out of the Agent's allowed envelope.
        var floor = DifficultyClassifier.minimumTier(for: result.difficulty)
        let escalated =
            DifficultyClassifier.shouldEscalate(
                confidence: result.confidence, threshold: confidenceThreshold,
                toolFailed: false, selfCritiqueFailed: false,
                attempt: request.attempt, maxAttempts: maxEscalationAttempts) || request.attempt > 0
        if escalated {
            floor = ModelTier(rawValue: min(ModelTier.premium.rawValue, floor.rawValue + request.attempt)) ?? .premium
        }

        // 6. Learned preference floated into `preferred`.
        var preferred = request.routing.preferredModels
        if let learned = outcomes.preferredModel(for: result.difficulty) { preferred = [learned] + preferred }

        // 7. Order (free-first/preferred/learned) and pick the first candidate at/above the
        //    floor. `bounded` already enforces the Agent's ceiling, so if nothing in the
        //    bounded set reaches the floor, the highest-tier bounded candidate is the best
        //    available — never a bounds violation, just a floor miss.
        let ordered = RouterOrdering.ordered(bounded, policy: policy, preferred: preferred)
        let atFloor = ordered.filter { $0.descriptor.tier >= floor }
        let pick = atFloor.first ?? ordered.last ?? bounded[0]

        // 8. Savings baseline = highest-tier capable+bounded model we did NOT pick.
        let baseline = bounded.max { $0.descriptor.tier < $1.descriptor.tier }
        let baselineModel = (baseline?.model != pick.model) ? baseline?.model : nil

        return RouterDecision(
            candidate: pick, tier: pick.descriptor.tier,
            reason: escalated
                ? "Escalated to \(pick.model) (attempt \(request.attempt + 1))."
                : "Routed to \(pick.model) for a \(result.difficulty) task.",
            escalated: escalated, baselineModel: baselineModel)
    }

    /// Synchronous, rule-only resolution for a subagent spawn: `budgetTier` is a hard
    /// ceiling, never a floor to escalate past.
    func route(forSubagent req: SubagentModelRequest) -> RouterDecision {
        let signal = TaskSignal(
            estimatedInputTokens: req.estimatedInputTokens,
            needsVision: req.needsVision, needsTools: req.needsTools, reasoningHeavy: false)
        let capable = RouterOrdering.capable(req.candidates, for: signal)
        let bounded = capable.filter { $0.descriptor.tier <= req.budgetTier }
        let ordered = RouterOrdering.ordered(bounded, policy: .saveMoney, preferred: [])
        let pick = ordered.first ?? capable.first ?? req.candidates.first ?? Self.synthetic()
        return RouterDecision(
            candidate: pick, tier: pick.descriptor.tier,
            reason: "Subagent routed to \(pick.model) (budget \(req.budgetTier)).",
            escalated: false, baselineModel: nil)
    }

    func recordOutcome(_ decision: RouterDecision, success: Bool) {
        let d = Self.difficulty(for: decision.tier)
        if success {
            outcomes.recordSuccess(difficulty: d, model: decision.candidate.model)
        } else {
            outcomes.recordFailure(difficulty: d, model: decision.candidate.model)
        }
    }

    func recordOverride(_ decision: RouterDecision) {
        outcomes.recordOverride(difficulty: Self.difficulty(for: decision.tier), model: decision.candidate.model)
    }

    private static func difficulty(for tier: ModelTier) -> Difficulty {
        switch tier {
        case .local, .free: return .trivial
        case .cheapPaid: return .moderate
        case .premium: return .hard
        }
    }

    private static func synthetic() -> RouterCandidate {
        RouterCandidate(
            connectionID: UUID(), model: "none",
            descriptor: ModelDescriptor(id: "none", tier: .local, contextWindow: 0, capabilities: []))
    }
}
