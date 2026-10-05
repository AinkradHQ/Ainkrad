import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// Docked approval bar shown just above the composer while a tool call awaits
/// the user's decision. The operation's details (identity/summary/diff) stay in
/// the inline transcript card; this bar carries only the decision so it's always
/// visible without scrolling. Seamless elevated surface with an accent cue —
/// matches the composer it sits above.
struct SageApprovalBar: View {
    let toolName: String
    let title: String
    let tokens: DesignTokens
    let onDeny: () -> Void
    let onApproveAlways: () -> Void
    let onApprove: () -> Void

    private var presentation: ToolPresentation { ToolPresentation.for(toolName: toolName) }
    private var tint: Color { presentation.tint == .primary ? tokens.accentPrimary : tokens.accentSecondary }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: presentation.icon)
                .font(.system(size: 12))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Approval required")
                    .font(AinkradFont.display(10, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(tokens.accentPrimary.opacity(0.85))
                Text(title)
                    .font(AinkradFont.display(12, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.85))
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            ToolCardButton(title: "Deny", tint: tokens.accentTertiary, filled: false, tokens: tokens, action: onDeny)
            ToolCardButton(
                title: "Allow always", tint: tokens.accentSecondary, filled: false, tokens: tokens,
                action: onApproveAlways)
            ToolCardButton(
                title: "Approve", tint: tokens.accentPrimary, filled: true, tokens: tokens, action: onApprove)
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

/// A tool-card action button with a hover highlight. `filled` renders the
/// primary (Approve) affordance as a solid accent chip; the others are text
/// buttons that gain a soft tinted fill on hover. (Moved here from
/// ToolCallCardView when the approval buttons were docked.)
private struct ToolCardButton: View {
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
