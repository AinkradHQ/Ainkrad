import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// The one Back idiom in the wizard, paired with each step's primary action.
///
/// Every step's footer goes through here so a future author finds ONE Back, not
/// one per screen. `.done` had a hand-rolled Back before this existed; it now
/// uses this too, with "Start using Ainkrad" as its primary title.
///
/// Back is ABSENT on the first step shown, not disabled — a greyed control the
/// user can never use is noise. It is never gated on the current step's own
/// validation: Back's whole purpose is to release someone the step will not let
/// through (above all the mandatory Providers step, where a connection that
/// will not verify would otherwise be a dead end).
struct SetupStepFooter: View {
    let coordinator: SetupCoordinator
    var primaryTitle: String = "Continue"
    /// Set when the step's requirements are unmet. The per-field messages are
    /// the real explanation and are rendered beside the fields themselves; this
    /// only decides whether the button is live.
    var isPrimaryDisabled: Bool = false
    var primaryIdentifier: String?
    /// Centres the primary action rather than pushing it to the trailing edge.
    ///
    /// For Welcome, which is a centred composition with a single action and no
    /// Back: a lone button hard against the right edge of a centred title card
    /// reads as left over from a form. Every other step IS a form, and the
    /// trailing edge is where its Continue belongs.
    var centersPrimary: Bool = false
    let primaryAction: () -> Void

    var body: some View {
        HStack {
            if coordinator.canGoBack {
                AinkradButton(title: "Back", style: .secondary) { coordinator.back() }
                    .accessibilityIdentifier("setup.back")
            }
            Spacer(minLength: 0)
            AinkradButton(title: primaryTitle, style: .primary, action: primaryAction)
                .disabled(isPrimaryDisabled)
                .accessibilityIdentifier(primaryIdentifier ?? "setup.continue")
            // The balancing spacer is what centres the button, and it is only
            // added when there is no Back — with one, "centred" would mean
            // "shoved right by the width of the Back button", which is neither.
            if centersPrimary, !coordinator.canGoBack {
                Spacer(minLength: 0)
            }
        }
        .padding(20)
    }
}

/// The inline explanation of an unmet requirement, rendered directly beneath the
/// field it is about. This is the half of "required" that a disabled button
/// cannot express on its own.
struct SetupRequirementNote: View {
    let message: String
    let tokens: DesignTokens

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 10))
            Text(message)
                .font(AinkradFont.display(11))
                .fixedSize(horizontal: false, vertical: true)
        }
        // `accentTertiary`, deliberately: it is what the Providers step already
        // uses for a FAILED connection, while `accentSecondary` is that step's
        // success colour (`checkmark.seal.fill`). An unmet requirement drawn in
        // the wizard's success colour is a contradiction.
        .foregroundStyle(tokens.accentTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
