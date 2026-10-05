import AinkradHostRuntime
import Foundation

/// Builds the user-directive text injected into the ensuing turn(s) after a plan
/// decision. Pure/testable — no session, no view.
enum PlanDirective {
    private static func numbered(_ plan: PlanArtifact) -> String {
        plan.steps.enumerated().map { "\($0.offset + 1). \($0.element.title)" }.joined(separator: "\n")
    }

    /// Approved plan → a directive the Build agent implements.
    static func build(from plan: PlanArtifact) -> String {
        var head = "Approved plan — implement it now, respecting the approval gate."
        if !plan.summary.isEmpty { head += "\n\nSummary: \(plan.summary)" }
        return head + "\n\nSteps:\n" + numbered(plan)
    }

    /// Rejected/iterate → feedback that keeps the Plan agent planning.
    static func revise(from plan: PlanArtifact) -> String {
        "Let's keep planning — do not build yet. Revise this plan and call present_plan "
            + "again with the improved version:\n\n" + numbered(plan)
    }
}

/// Derives whether the transcript currently has an unactioned plan awaiting the
/// user's decision. A user *text* message appearing AFTER the latest
/// `present_plan` call (the approve/keep-planning directive, or any new prompt)
/// clears it — the plan is no longer the current step. Pure/testable.
enum PlanTurnHeuristics {
    static func pendingPlan(in messages: [AgentMessage]) -> PlanArtifact? {
        var found: PlanArtifact?
        for message in messages {
            if message.role == .user,
                message.content.contains(where: {
                    if case .text(let t) = $0 { return !t.isEmpty } else { return false }
                })
            {
                found = nil  // a user prompt/directive supersedes any earlier plan
                continue
            }
            for block in message.content {
                if case .toolUse(_, let name, let input) = block, name == "present_plan" {
                    found = PlanArtifact.from(input) ?? found
                }
            }
        }
        return found
    }
}

/// Composes the plan decision from the existing seams — flipping the shared
/// `AgentStore` (the same store the composer's `AgentSwitcherView` drives) and
/// `AgentSession.send`. Deliberately NO new `AgentSession` state or gate change.
@MainActor
enum PlanFlow {
    /// Approve & Build: switch Plan→Build, then send the approved plan as a
    /// directive so the Build agent implements it.
    static func approveBuild(plan: PlanArtifact, session: AgentSession, store: AgentStore) {
        store.setActive(BuiltInAgents.buildID)
        session.send(PlanDirective.build(from: plan))
    }

    /// Keep planning: stay in Plan and feed the plan back as a revision request.
    static func keepPlanning(plan: PlanArtifact, session: AgentSession) {
        session.send(PlanDirective.revise(from: plan))
    }
}
