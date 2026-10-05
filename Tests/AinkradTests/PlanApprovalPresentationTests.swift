import Foundation
import Testing

@testable import Ainkrad

@Suite struct PlanApprovalPresentationTests {
    @Test func titleUsesSummaryWhenPresent() {
        let plan = PlanArtifact(summary: "Ship the widget", steps: [PlanStep(title: "a")])
        #expect(PlanApprovalPresentation.title(for: plan) == "Ship the widget")
    }

    @Test func titleFallsBackToStepCount() {
        let plan = PlanArtifact(summary: "", steps: [PlanStep(title: "a"), PlanStep(title: "b")])
        #expect(PlanApprovalPresentation.title(for: plan) == "2 steps")
    }
}
