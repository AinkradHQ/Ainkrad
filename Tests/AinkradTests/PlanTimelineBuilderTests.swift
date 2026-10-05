import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite struct PlanTimelineBuilderTests {
    private func planCall(_ id: String, summary: String) -> AgentContentBlock {
        .toolUse(
            id: id, name: "present_plan",
            input: .object([
                "summary": .string(summary),
                "steps": .array([.object(["title": .string("step one")])]),
            ]))
    }

    @Test func presentPlanBecomesPlanStepNotToolStep() {
        let msgs = [
            AgentMessage(role: .user, text: "plan it"),
            AgentMessage(role: .assistant, content: [planCall("p1", summary: "first")]),
            AgentMessage(role: .user, content: [.toolResult(toolUseID: "p1", content: "ok", isError: false)]),
        ]
        guard case .agentTurn(_, let steps) = TranscriptTimelineBuilder.build(from: msgs)[1] else {
            Issue.record("expected agent turn")
            return
        }
        #expect(steps.count == 1)
        guard case .plan(let plan) = steps[0].kind else {
            Issue.record("not a plan step")
            return
        }
        #expect(plan.summary == "first")
        #expect(plan.steps.map(\.title) == ["step one"])
    }

    @Test func repeatedPresentPlanCollapsesToLatest() {
        let msgs = [
            AgentMessage(role: .user, text: "go"),
            AgentMessage(role: .assistant, content: [planCall("p1", summary: "draft"), .text("thinking")]),
            AgentMessage(role: .assistant, content: [planCall("p2", summary: "final")]),
        ]
        guard case .agentTurn(_, let steps) = TranscriptTimelineBuilder.build(from: msgs)[1] else {
            Issue.record("expected agent turn")
            return
        }
        let plans = steps.compactMap { step -> PlanArtifact? in
            if case .plan(let p) = step.kind { return p } else { return nil }
        }
        #expect(plans.count == 1)  // only the latest survives
        #expect(plans[0].summary == "final")
    }
}
