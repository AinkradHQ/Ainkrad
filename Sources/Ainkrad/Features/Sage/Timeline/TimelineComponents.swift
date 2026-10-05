import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// The rail's leading gutter: a full-height tinted spine with a status node
/// marker at its top. Shared by committed steps, the live tail, and the pending
/// approval node so every rail node is identical by construction (not by
/// hand-copied markup).
struct TimelineRailGutter: View {
    let status: StepStatus
    let tokens: DesignTokens
    let reduceMotion: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(tokens.accentPrimary.opacity(0.25))
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            TimelineNodeMarker(
                status: status, tint: tokens.accentPrimary,
                errorColor: tokens.danger, reduceMotion: reduceMotion
            )
            .padding(.top, 3)
        }
        .frame(width: 10)
    }
}

/// The "Thinking" disclosure row shared by committed thinking steps and the live
/// tail. Expansion state is owned by the caller (a committed turn keys it by
/// step id; the live tail holds a single bool), passed in as `isExpanded` +
/// `onToggle` so the row itself stays stateless.
struct TimelineThinkingRow: View {
    let text: String
    let isExpanded: Bool
    let tokens: DesignTokens
    let reduceMotion: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(reduceMotion ? nil : AinkradMotion.present) { onToggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right").font(.system(size: 9))
                    Text("Thinking").font(AinkradFont.display(11, weight: .medium)).kerning(1)
                }
                .foregroundStyle(tokens.accentSecondary.opacity(0.85))
            }
            .buttonStyle(.plain)
            if isExpanded {
                Text(text)
                    .font(AinkradFont.mono(11))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
                    .textSelection(.enabled)
            }
        }
    }
}
