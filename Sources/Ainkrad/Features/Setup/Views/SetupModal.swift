import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// A decision the wizard has to stop for, raised by a step and presented by
/// `SetupOverlayView` above the whole gate.
///
/// This overturns an earlier rule that every failure rendered INLINE, on the
/// reasoning that stacking a modal over a modal is how the launch-time alerts
/// became unverifiable. Hand-testing killed it twice: the vault confirmation
/// went below the fold on the step's own scroller with its two buttons off
/// screen, and so did the refusal — a five-line explanation of why a folder was
/// rejected, which the user had to scroll to discover.
///
/// The rule now is about ATTENTION, not severity. Anything the wizard raises in
/// response to an action the user just took is presented over the wizard, so it
/// cannot be missed and cannot be scrolled away from. Inline is for things that
/// are simply part of the screen — the folder preview, the migration notice.
@MainActor
@Observable
final class SetupModalPresenter {
    struct Modal: Identifiable {
        enum Tone {
            /// Something is being confirmed rather than warned about.
            case informational
            /// The action is destructive or irreversible.
            case caution
        }

        let id = UUID()
        let title: String
        let message: String
        let icon: String
        let tone: Tone
        let primaryTitle: String
        let primary: () -> Void
        /// Optional: a refusal has one way out, a decision has two. Rendering an
        /// invented second button on a refusal would make it look like a choice
        /// the user does not actually have.
        var secondaryTitle: String?
        var secondary: (() -> Void)?
        /// What a click on the scrim, or Esc, does. Always the SAFE outcome — never the
        /// primary — so a stray click can never confirm anything.
        let onDismiss: () -> Void
    }

    var modal: Modal?

    func present(_ modal: Modal) { self.modal = modal }
    func dismiss() { modal = nil }

    /// A scrim click or Esc: clears the modal and runs its `onDismiss`, the
    /// safe outcome, so a stray click can never confirm anything.
    func cancel() {
        let cancelled = modal
        modal = nil
        cancelled?.onDismiss()
    }
}

/// The modal's content: the tone's icon and title, a message that scrolls only
/// when it has to, and the buttons.
///
/// Presented by `SetupOverlayView` through the kit's `ainkradModal`, which owns
/// the scrim, the blur behind it, the panel, Esc and the materialize — and
/// centres it in the WHOLE gate, not in the step's content group, so it cannot
/// be scrolled away from.
struct SetupModalView: View {
    let modal: SetupModalPresenter.Modal
    let tokens: DesignTokens

    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s18) {
            HStack(alignment: .firstTextBaseline, spacing: skin.size.s10) {
                Image(systemName: modal.icon)
                    .font(skin.font(AinkradFontToken(sizeKey: "t14", weight: "medium", scaled: false)))
                    .foregroundStyle(tint)
                Text(modal.title)
                    .font(AinkradFont.display(16, weight: .semibold))
                    .foregroundStyle(tokens.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Scrolls only if it has to. A refusal can run to several
            // paragraphs, and the card must not grow past the window on a
            // short display — but the buttons below stay outside this
            // scroller, so they are never the thing that gets clipped.
            ScrollView {
                Text(modal.message)
                    .font(AinkradFont.display(13))
                    .foregroundStyle(tokens.foreground.opacity(skin.opacity.o80))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: skin.size.s260)
            .scrollBounceBehavior(.basedOnSize)

            HStack(spacing: skin.size.s10) {
                Spacer(minLength: 0)
                if let secondaryTitle = modal.secondaryTitle, let secondary = modal.secondary {
                    AinkradButton(title: secondaryTitle, style: .secondary, action: secondary)
                        .accessibilityIdentifier("setup.modal.secondary")
                }
                AinkradButton(title: modal.primaryTitle, style: .primary) {
                    modal.primary()
                }
                .accessibilityIdentifier("setup.modal.primary")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(modal.title)
        .accessibilityIdentifier("setup.modal")
    }

    /// The tone reads from the icon: a caution in the warning accent, a
    /// confirmation in the secondary one.
    private var tint: Color {
        switch modal.tone {
        case .informational: return tokens.accentSecondary
        case .caution: return tokens.accentTertiary
        }
    }
}
