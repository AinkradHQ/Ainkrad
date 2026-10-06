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

/// Docked decision bar shown just above the composer while a gated tool call or
/// an agent-authored plan awaits the user's decision. The details (the tool's
/// identity/summary/diff, the plan's steps in `PlanCardView`) stay in the inline
/// transcript; this bar carries only the decision, so it is always visible
/// without scrolling. Seamless elevated surface with an accent cue — matches
/// the composer it sits above.
struct SageDecisionBar: View {
    /// One button on the bar, drawn as a kit `AinkradButton` in `style` —
    /// `.primary` for the affirmative decision, `.ghost` for the others.
    struct Action {
        let title: String
        let style: AinkradButtonStyle
        let perform: () -> Void
    }

    let content: SageDecisionBarContent
    let actions: [Action]
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: content.icon)
                .font(.system(size: 12))
                .foregroundStyle(content.iconTint == .primary ? theme.accentPrimary : theme.accentSecondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(content.caption)
                    .font(AinkradFont.display(10, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(theme.accentPrimary.opacity(0.85))
                Text(content.title)
                    .font(AinkradFont.display(12, weight: .medium))
                    .foregroundStyle(theme.foreground.opacity(0.85))
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            ForEach(actions.indices, id: \.self) { index in
                AinkradButton(title: actions[index].title, style: actions[index].style, action: actions[index].perform)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChamferShape(cut: AinkradRadius.md).fill(theme.surfaceElevated.opacity(0.6)))
        .overlay {
            ChamferShape(cut: AinkradRadius.md).stroke(theme.accentPrimary.opacity(0.55), lineWidth: 1)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }
}
