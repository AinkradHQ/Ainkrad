import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// The opening step, and the first screen anyone ever sees in Ainkrad.
///
/// The only step on a CENTRED axis rather than a left-aligned column: the mark,
/// the headline, the copy and the single action stack on one line of symmetry.
/// Every other step is a form and reads correctly left-aligned; this one is a
/// title card and does not.
///
/// The mark and the headline above this content belong to `SetupStage`, not to
/// this view — see `SetupStep.usesHeroMark`. The stage renders ONE mark for the
/// whole wizard and moves it between the hero arrangement here and the small
/// inline one beside every later heading, which is why this screen does not draw
/// its own: two marks could not animate into each other.
///
/// The copy is deliberately ONE idea: the folder promise, because it is the one
/// thing the very next screen needs the user to already believe. An earlier pass
/// carried three paragraphs, which is three ideas set as prose. What was cut:
/// the "one surface" point (the headline already makes it in nine words) and the
/// "here is what the next few screens ask" paragraph (that is the progress
/// rail's job, and the rail is on screen while it is being read).
///
/// It writes nothing and asks nothing. No Back button appears because there is
/// nowhere behind it — `SetupStepFooter` omits rather than disables Back on the
/// first step — and no skip, because the gate is total.
struct SetupWelcomeStepView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @Environment(\.setupGroupWidth) private var groupWidth

    let coordinator: SetupCoordinator

    /// Drives the entry: the copy settles a beat after the mark and headline
    /// land, rather than the screen arriving as one block. Flat off under
    /// reduce-motion, where the offset and delay both collapse to zero because
    /// `SetupStageMotion.layerGeometry` returns `nil`.
    @State private var hasSettled = false

    var body: some View {
        let tokens = environment.themeManager.tokens

        VStack(spacing: 0) {
            paragraph(tokens: tokens)
                // Narrower than the reading measure: CENTRED text needs a
                // shorter line than left-aligned text, because the eye has no
                // fixed left edge to return to.
                .frame(maxWidth: SetupStageLayout.readingWidth(inGroupOf: groupWidth) * 0.8)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 20)

            // No Back appears here: `SetupStepFooter` omits it on the first step
            // shown, which for a fresh install is this one — which is also what
            // lets `centersPrimary` genuinely centre.
            SetupStepFooter(
                coordinator: coordinator,
                primaryTitle: "Get Started",
                primaryIdentifier: "setup.welcome.continue",
                centersPrimary: true
            ) {
                coordinator.advance()
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { settle() }
    }

    private func paragraph(tokens: DesignTokens) -> some View {
        let size: CGFloat = 16
        let geometry = SetupStageMotion.layerGeometry(
            .content,
            reduceMotion: reduceMotion,
            isForward: true)
        // `nil` geometry is reduce-motion: no lift, no stagger, nothing to fade
        // from. The text is simply there.
        let lift = geometry.map(\.lift) ?? 0
        let delay = geometry.map(\.delay) ?? 0

        return Text(
            "Everything you and your agents make — your workspaces, your notes, "
                + "your skills, every conversation you have — is kept as ordinary "
                + "files in a single folder on your Mac. Not a database, not an "
                + "account somewhere. A folder you can open, back up, or carry to "
                + "another machine."
        )
        .font(AinkradFont.display(size))
        .foregroundStyle(tokens.foreground.opacity(0.82))
        .lineSpacing(size * 0.36)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .opacity(hasSettled ? 1 : 0)
        .offset(y: hasSettled ? 0 : lift)
        .animation(
            SetupStageMotion.animation(
                reduceMotion: reduceMotion,
                layer: .content)?.delay(delay),
            value: hasSettled)
    }

    /// Routed through `SetupStageMotion` rather than a bare `.animation(...)`,
    /// so the wizard has exactly one place where reduce-motion is honoured.
    private func settle() {
        guard !hasSettled else { return }
        withAnimation(
            SetupStageMotion.animation(
                reduceMotion: reduceMotion,
                layer: .content)
        ) {
            hasSettled = true
        }
    }
}
