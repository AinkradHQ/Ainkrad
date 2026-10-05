import Foundation

/// The unit of work handed to a subagent: a prompt plus the scoping that
/// bounds what it's allowed to do.
///
/// PROVISIONAL — `ModelTier` is provided by Slice 5's Router. Confirm at execution.
struct SubagentSpec: Sendable, Identifiable {
    let id: UUID
    let prompt: String
    /// Selects an `AgentProfile`; `nil` = the caller's own profile.
    let profileID: UUID?
    /// Empty = the profile's full tool set.
    let toolAllowList: [String]
    /// Model CLASS the router resolves to a concrete model.
    let budgetTier: ModelTier

    init(
        id: UUID = UUID(), prompt: String, profileID: UUID? = nil,
        toolAllowList: [String] = [], budgetTier: ModelTier
    ) {
        self.id = id
        self.prompt = prompt
        self.profileID = profileID
        self.toolAllowList = toolAllowList
        self.budgetTier = budgetTier
    }
}

enum SubagentStatus: String, Sendable, Equatable { case succeeded, failed }

/// One outcome per spec — always produced, even on failure (failure isolation).
struct SubagentOutcome: Sendable, Equatable, Identifiable {
    let id: UUID
    let status: SubagentStatus
    let resultText: String
}

/// Executes a single `SubagentSpec`. Production implementation lands in a
/// later task; tests supply a controllable stub. Must never throw out of
/// `run` — a runner that hits an internal error reports it as a `.failed`
/// outcome rather than propagating.
@MainActor
protocol SubagentRunner: AnyObject {
    func run(_ spec: SubagentSpec) async -> SubagentOutcome
}
