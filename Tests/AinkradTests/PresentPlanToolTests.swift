import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("PresentPlanTool")
@MainActor
struct PresentPlanToolTests {
    private var samplePlan: JSONValue {
        .object([
            "summary": .string("Ship the widget"),
            "steps": .array([
                .object(["title": .string("Wire the store")]),
                .object(["title": .string("Add the view")]),
            ]),
        ])
    }

    @Test func echoesPlanAndTellsModelToStop() async throws {
        let r = try await PresentPlanTool().execute(samplePlan)
        #expect(!r.isError)
        #expect(r.content.contains("Wire the store"))
        #expect(r.content.contains("Add the view"))
        #expect(r.content.lowercased().contains("wait"))  // instructs the model to end the turn
    }

    @Test func permissionIsMemoryClass() {
        #expect(PresentPlanTool().permission == .memory)
    }

    @Test func autoApprovesEvenWhenReadsAreGated() {
        let decision = AgentPermissionPolicy.decide(
            toolPermission: PresentPlanTool().permission, toolName: "present_plan",
            mode: .ask, allowlist: [], gateReads: true, isIrreversible: false)
        #expect(decision == .autoApprove)  // memory-class is exempt even with gateReads on
    }

    @Test func emptyStepsIsError() async throws {
        let r = try await PresentPlanTool().execute(.object(["steps": .array([])]))
        #expect(r.isError)
    }
}
