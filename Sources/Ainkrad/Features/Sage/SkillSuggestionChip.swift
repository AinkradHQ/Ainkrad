import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// A passive, dismissable prompt shown after a complex clean turn: "This looked
/// reusable — capture it as a skill?". Accept sends the reflection directive
/// (the agent drafts via `propose_skill`, which never auto-installs); dismiss
/// hides it. Presentation-only; all safety lives on `AgentSession`.
struct SkillSuggestionChip: View {
    @Environment(\.ainkradSkin) private var skin
    let session: AgentSession
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        if let suggestion = session.pendingSkillSuggestion {
            HStack(spacing: skin.size.s10) {
                Image(systemName: "wand.and.stars")
                    .font(skin.font(AinkradFontToken(sizeKey: "t12", weight: "semibold", scaled: false)))
                    .foregroundStyle(theme.accentSecondary)
                Text("This looked reusable — capture it as a skill?")
                    .font(AinkradFont.display(12, weight: .medium))
                    .foregroundStyle(theme.foreground.opacity(skin.opacity.o90))
                Spacer(minLength: 8)
                AinkradButton(title: "Capture", style: .primary) {
                    session.acceptSkillSuggestion()
                }
                .accessibilityLabel(
                    "Capture as skill — the procedure using \(suggestion.toolNames.joined(separator: ", "))")
                AinkradButton(title: "Dismiss", style: .ghost) {
                    session.dismissSkillSuggestion()
                }
                .accessibilityLabel("Dismiss skill suggestion")
            }
            .padding(.horizontal, skin.spacing.md)
            .padding(.vertical, skin.spacing.sm)
            .background(skin.shape(cut: 10).fill(theme.surfaceElevated))
        }
    }
}
