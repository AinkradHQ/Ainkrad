import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// A passive, dismissable prompt shown after a complex clean turn: "This looked
/// reusable — capture it as a skill?". Accept sends the reflection directive
/// (the agent drafts via `propose_skill`, which never auto-installs); dismiss
/// hides it. Presentation-only; all safety lives on `AgentSession`.
struct SkillSuggestionChip: View {
    let session: AgentSession
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        if let suggestion = session.pendingSkillSuggestion {
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.accentSecondary)
                Text("This looked reusable — capture it as a skill?")
                    .font(AinkradFont.display(12, weight: .medium))
                    .foregroundStyle(theme.foreground.opacity(0.9))
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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(ChamferShape().fill(theme.surfaceElevated))
        }
    }
}
