import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// What the docked decision bar says: its glyph, caps caption and one-line
/// title. Pure, so both decisions' wording is testable without SwiftUI.
struct SageDecisionBarContent: Equatable {
    let icon: String
    let iconTint: ToolTint
    let caption: String
    let title: String

    /// A gated tool call awaiting approval: the tool's own glyph and tint.
    static func toolApproval(toolName: String, title: String) -> Self {
        let presentation = ToolPresentation.for(toolName: toolName)
        return Self(icon: presentation.icon, iconTint: presentation.tint, caption: "Approval required", title: title)
    }

    /// An agent-authored plan awaiting the user's decision: its summary, or its
    /// step count when it has none.
    static func plan(_ plan: PlanArtifact) -> Self {
        Self(
            icon: "list.bullet.clipboard", iconTint: .secondary, caption: "Plan ready",
            title: plan.summary.isEmpty ? PlanStepPresentation.stepCountLabel(plan.steps.count) : plan.summary)
    }
}

/// Sage's docked decision bar: the kit's `AinkradDecisionBar` fed Sage's wording
/// (`SageDecisionBarContent`). The details stay in the inline transcript.
struct SageDecisionBar: View {
    let content: SageDecisionBarContent
    let actions: [AinkradDecisionBar.Action]

    var body: some View {
        AinkradDecisionBar(
            icon: content.icon, iconTint: content.iconTint == .primary ? .primary : .secondary,
            caption: content.caption, title: content.title, actions: actions)
    }
}
