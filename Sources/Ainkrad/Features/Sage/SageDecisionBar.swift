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
    /// One button on the bar. `filled` renders the primary affordance as a solid
    /// accent chip; the others are text buttons that gain a soft fill on hover.
    struct Action {
        let title: String
        let tint: Color
        let filled: Bool
        let perform: () -> Void
    }

    let content: SageDecisionBarContent
    let actions: [Action]
    let tokens: DesignTokens

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: content.icon)
                .font(.system(size: 12))
                .foregroundStyle(content.iconTint == .primary ? tokens.accentPrimary : tokens.accentSecondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(content.caption)
                    .font(AinkradFont.display(10, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(tokens.accentPrimary.opacity(0.85))
                Text(content.title)
                    .font(AinkradFont.display(12, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.85))
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            ForEach(actions.indices, id: \.self) { index in
                DecisionButton(action: actions[index])
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.6)))
        .overlay {
            ChamferShape(cut: AinkradRadius.md).stroke(tokens.accentPrimary.opacity(0.55), lineWidth: 1)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }
}

/// A decision-bar button with a hover highlight.
private struct DecisionButton: View {
    let action: SageDecisionBar.Action
    @State private var isHovering = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let tint = action.tint
        Button(action: action.perform) {
            Text(action.title)
                .font(AinkradFont.display(12, weight: action.filled ? .semibold : .regular))
                .foregroundStyle(action.filled ? tint.hostContrastingText : tint.opacity(isHovering ? 1 : 0.85))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(
                    ChamferShape(cut: AinkradRadius.sm)
                        .fill(action.filled ? tint.opacity(0.9) : tint.opacity(isHovering ? 0.18 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : AinkradMotion.hover, value: isHovering)
    }
}
