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
        /// What a click on the scrim does. Always the SAFE outcome — never the
        /// primary — so a stray click can never confirm anything.
        let onDismiss: () -> Void
    }

    var modal: Modal?

    func present(_ modal: Modal) { self.modal = modal }
    func dismiss() { modal = nil }
}

/// The modal itself: a scrim over the wizard and one centred card.
///
/// Sized to its content and centred in the WINDOW, not in the step's content
/// group — the whole point is that it cannot be scrolled away from.
struct SetupModalView: View {
    @Environment(AppEnvironment.self) private var environment

    let modal: SetupModalPresenter.Modal
    let tokens: DesignTokens

    var body: some View {
        ZStack {
            // Blurs the WIZARD behind it, rather than merely dimming it. The
            // workspace is already blurred at 14pt by `RootView` when the gate
            // is up, so a solid scrim here would be the one flat black plane in
            // a stack of otherwise translucent surfaces.
            //
            // A light tint over the blur keeps the card's edge readable — blur
            // alone leaves the layers the same brightness and the boundary
            // disappears.
            ZStack {
                VisualEffectBlur()
                tokens.background.opacity(0.28)
            }
            .ignoresSafeArea()
            .onTapGesture { modal.onDismiss() }

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: modal.icon)
                        .font(.system(size: 14, weight: .medium))
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
                        .foregroundStyle(tokens.foreground.opacity(0.8))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 260)
                .scrollBounceBehavior(.basedOnSize)

                HStack(spacing: 10) {
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
            .padding(24)
            .frame(width: 460)
            // The app's shared panel finish, exactly as the Launcher, Settings
            // and Quit panels use it: translucent, blurred, chamfered, with the
            // Cardinal HUD edge ring. It reads the user's own overlay opacity
            // and blur settings live, so this modal cannot end up as the one
            // surface in the app that ignores them.
            .hudPanelChrome(tokens: tokens)
            .overlay(
                // The tone's tint on top of the shared ring, so a caution reads
                // as one at a glance without replacing the panel's identity.
                ChamferShape(cut: OverlayChrome.cornerRadius)
                    .strokeBorder(tint.opacity(0.4), lineWidth: 1)
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(modal.title)
        .accessibilityIdentifier("setup.modal")
    }

    private var tint: Color {
        switch modal.tone {
        case .informational: return tokens.accentSecondary
        case .caution: return tokens.accentTertiary
        }
    }
}
