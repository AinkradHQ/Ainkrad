import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// Pure title helper for the plan approval bar.
enum PlanApprovalPresentation {
    static func title(for plan: PlanArtifact) -> String {
        plan.summary.isEmpty ? PlanStepPresentation.stepCountLabel(plan.steps.count) : plan.summary
    }
}

/// Docked decision bar shown just above the composer while an agent-authored
/// plan awaits the user's decision. The plan's steps stay in the inline
/// `PlanCardView` rail node; this bar carries only the decision, always visible
/// without scrolling — the same split `SageApprovalBar` uses for gated
/// tools. Seamless elevated surface with an accent cue.
struct PlanApprovalBar: View {
    let plan: PlanArtifact
    let tokens: DesignTokens
    let onKeepPlanning: () -> Void
    let onApproveBuild: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 12))
                .foregroundStyle(tokens.accentSecondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Plan ready")
                    .font(AinkradFont.display(10, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(tokens.accentPrimary.opacity(0.85))
                Text(PlanApprovalPresentation.title(for: plan))
                    .font(AinkradFont.display(12, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.85))
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            PlanBarButton(
                title: "Keep planning", tint: tokens.accentTertiary, filled: false,
                tokens: tokens, action: onKeepPlanning)
            PlanBarButton(
                title: "Approve & Build", tint: tokens.accentPrimary, filled: true,
                tokens: tokens, action: onApproveBuild)
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

private struct PlanBarButton: View {
    let title: String
    let tint: Color
    let filled: Bool
    let tokens: DesignTokens
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AinkradFont.display(12, weight: filled ? .semibold : .regular))
                .foregroundStyle(filled ? tint.hostContrastingText : tint.opacity(isHovering ? 1 : 0.85))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(
                    ChamferShape(cut: AinkradRadius.sm)
                        .fill(filled ? tint.opacity(0.9) : tint.opacity(isHovering ? 0.18 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : AinkradMotion.hover, value: isHovering)
    }
}
