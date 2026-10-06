import Foundation
import Testing

@testable import Ainkrad

/// The one docked decision bar carries both decisions; pin what each says.
@Suite struct SageDecisionBarTests {
    @Test func planTitleUsesSummaryWhenPresent() {
        let plan = PlanArtifact(summary: "Ship the widget", steps: [PlanStep(title: "a")])
        let content = SageDecisionBarContent.plan(plan)
        #expect(content.title == "Ship the widget")
        #expect(content.caption == "Plan ready")
        #expect(content.icon == "list.bullet.clipboard")
        #expect(content.iconTint == .secondary)
    }

    @Test func planTitleFallsBackToStepCount() {
        let plan = PlanArtifact(summary: "", steps: [PlanStep(title: "a"), PlanStep(title: "b")])
        #expect(SageDecisionBarContent.plan(plan).title == "2 steps")
    }

    @Test func toolApprovalShowsThePreviewTitleWithTheToolsGlyph() {
        let content = SageDecisionBarContent.toolApproval(toolName: "edit_file", title: "Edit a.txt")
        #expect(content.title == "Edit a.txt")
        #expect(content.caption == "Approval required")
        #expect(content.icon == ToolPresentation.for(toolName: "edit_file").icon)
        #expect(content.iconTint == .primary)
        #expect(SageDecisionBarContent.toolApproval(toolName: "run_terminal", title: "t").iconTint == .secondary)
    }
}
