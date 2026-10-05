import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("PlanFlow")
@MainActor
struct PlanFlowTests {
    private var plan: PlanArtifact {
        PlanArtifact(
            summary: "Ship the widget",
            steps: [PlanStep(title: "Wire the store"), PlanStep(title: "Add the view")])
    }

    private func planCall(_ id: String) -> AgentContentBlock {
        .toolUse(
            id: id, name: "present_plan",
            input: .object([
                "summary": .string("Ship the widget"),
                "steps": .array([
                    .object(["title": .string("Wire the store")]),
                    .object(["title": .string("Add the view")]),
                ]),
            ]))
    }

    @Test func buildDirectiveCarriesSummaryAndSteps() {
        let text = PlanDirective.build(from: plan)
        #expect(text.contains("Ship the widget"))
        #expect(text.contains("Wire the store"))
        #expect(text.contains("Add the view"))
        #expect(text.lowercased().contains("implement"))
    }

    @Test func reviseDirectiveAsksToKeepPlanning() {
        let text = PlanDirective.revise(from: plan)
        #expect(text.lowercased().contains("keep planning") || text.lowercased().contains("revise"))
        #expect(text.contains("Wire the store"))
    }

    @Test func pendingPlanDetectedWhenPlanIsLastActivity() {
        let msgs = [
            AgentMessage(role: .user, text: "plan it"),
            AgentMessage(role: .assistant, content: [planCall("p1")]),
            AgentMessage(role: .user, content: [.toolResult(toolUseID: "p1", content: "ok", isError: false)]),
        ]
        #expect(PlanTurnHeuristics.pendingPlan(in: msgs)?.summary == "Ship the widget")
    }

    @Test func pendingPlanClearedByLaterUserText() {
        let msgs = [
            AgentMessage(role: .user, text: "plan it"),
            AgentMessage(role: .assistant, content: [planCall("p1")]),
            AgentMessage(role: .user, content: [.toolResult(toolUseID: "p1", content: "ok", isError: false)]),
            AgentMessage(role: .user, text: "Approved plan — implement it"),
        ]
        #expect(PlanTurnHeuristics.pendingPlan(in: msgs) == nil)
        #expect(PlanTurnHeuristics.pendingPlan(in: [AgentMessage(role: .user, text: "hi")]) == nil)
    }

    @Test func approveBuildSwitchesToBuildAndSendsDirective() {
        let store = AgentStore(persistence: InMemoryPersistenceStore())
        store.setActive(BuiltInAgents.planID)
        let session = TestSessionFactory.make(agents: store)
        session.replaceMessages([AgentMessage(role: .assistant, content: [planCall("p1")])])

        PlanFlow.approveBuild(plan: plan, session: session, store: store)

        #expect(store.active.id == BuiltInAgents.buildID)
        #expect(session.messages.last?.text.contains("Wire the store") == true)
        session.interrupt()  // cancel the dangling turn Task; keeps the suite from lingering
    }

    @Test func keepPlanningStaysInPlanAndSendsRevision() {
        let store = AgentStore(persistence: InMemoryPersistenceStore())
        store.setActive(BuiltInAgents.planID)
        let session = TestSessionFactory.make(agents: store)
        session.replaceMessages([AgentMessage(role: .assistant, content: [planCall("p1")])])

        PlanFlow.keepPlanning(plan: plan, session: session)

        #expect(store.active.id == BuiltInAgents.planID)
        #expect(
            session.messages.last?.text.lowercased().contains("keep planning") == true
                || session.messages.last?.text.lowercased().contains("revise") == true)
        session.interrupt()
    }
}
