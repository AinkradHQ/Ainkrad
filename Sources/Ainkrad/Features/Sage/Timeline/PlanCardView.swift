import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// Pure presentation helpers for the plan node (no SwiftUI), unit-tested like
/// `TodoStepPresentation`.
enum PlanStepPresentation {
    static func number(_ index: Int) -> String { "\(index + 1)" }
    static func stepCountLabel(_ count: Int) -> String {
        "\(count) step\(count == 1 ? "" : "s")"
    }
}

/// The agent's proposed plan rendered as a single timeline node: a chamfered
/// panel with a "Plan" header, an optional summary, and an ordered step list
/// with numbered badges. No separators; no action buttons — the Approve & Build
/// / Keep planning decision lives in the docked `SageDecisionBar` (Task 7),
/// mirroring how a gated tool's card stays in the rail while its buttons dock
/// above the composer.
struct PlanCardView: View {
    @Environment(\.ainkradSkin) private var skin
    let plan: PlanArtifact
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: skin.spacing.sm) {
            HStack(spacing: skin.size.s6) {
                Image(systemName: "list.bullet.clipboard").font(skin.font(AinkradFontToken(sizeKey: "t11", scaled: false)))
                    .foregroundStyle(theme.accentSecondary)
                Text("Plan").font(AinkradFont.display(11, weight: .semibold)).kerning(1)
                    .foregroundStyle(theme.accentSecondary.opacity(skin.opacity.o85))
                Spacer(minLength: 8)
                Text(PlanStepPresentation.stepCountLabel(plan.steps.count))
                    .font(AinkradFont.mono(10)).foregroundStyle(theme.foreground.opacity(skin.opacity.o50))
            }
            if !plan.summary.isEmpty {
                Text(plan.summary)
                    .font(AinkradFont.display(12, weight: .medium))
                    .foregroundStyle(theme.foreground.opacity(skin.opacity.o85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: skin.size.s6) {
                ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                    row(index: index, step: step)
                }
            }
        }
        .padding(.horizontal, skin.size.s10).padding(.vertical, skin.spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChamferShape(cut: AinkradRadius.sm).fill(theme.background.opacity(skin.opacity.o45)))
        .overlay {
            ChamferShape(cut: AinkradRadius.sm).stroke(theme.accentSecondary.opacity(skin.opacity.o22), lineWidth: 1)
        }
    }

    private func row(index: Int, step: PlanStep) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: skin.spacing.sm) {
            Text(PlanStepPresentation.number(index))
                .font(AinkradFont.mono(10, weight: .semibold))
                .foregroundStyle(theme.accentSecondary)
                .frame(minWidth: skin.size.s16, alignment: .trailing)
            Text(step.title)
                .font(AinkradFont.display(12))
                .foregroundStyle(theme.foreground.opacity(skin.opacity.o85))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
