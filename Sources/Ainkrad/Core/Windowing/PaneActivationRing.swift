import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// The pane's border and targeting brackets — and the activation pulse that
/// replaced the content cross-fade as the tab transition.
///
/// When this pane becomes the focused one its accent border flares to full
/// strength and thickens slightly, then settles back over ~320ms, and the
/// brackets snap in. The effect is that the pane you switched to visibly "comes
/// alive" — motion the eye can follow — while the content underneath it never
/// changes opacity, so nothing flashes and no two terminals ever ghost through
/// each other.
///
/// Strokes only, and no shadow: a 1px path costs nothing to animate, where the
/// shadow this file used to animate was an offscreen render pass per frame.
struct PaneActivationRing: View {
    let isFocused: Bool

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    /// 1 at the instant of activation, easing to 0. Drives both the border's
    /// brightness and its width, so the flare reads as light rather than as the
    /// frame changing size.
    @State private var pulse: Double = 0

    var body: some View {
        ZStack {
            skin.shape(cut: skin.radius.md)
                .strokeBorder(borderColor, lineWidth: 1 + pulse * 0.6)

            TargetingBrackets(length: skin.size.s10)
                .stroke(bracketColor, lineWidth: 1.5)
                .padding(-skin.size.s2)
        }
        .onChange(of: isFocused) { _, focused in
            guard focused, !reduceMotion else { return }
            // Set the start value, then animate to rest on the next tick, so
            // the flare actually renders at full strength before it decays.
            // `DispatchQueue.main.async` on purpose (S-CON-5): the decay must
            // start on the next run-loop turn, after the full-strength frame
            // has been committed.
            pulse = 1
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: skin.motion.durations.d0_32)) { pulse = 0 }
            }
        }
    }

    /// Colours come from `hostSkin`, which carries the user's custom accent;
    /// every scalar comes from the environment's skin.
    private var tokens: AinkradSkin { environment.themeManager.hostSkin }

    private var borderColor: Color {
        guard isFocused else { return tokens.color(\.foreground).opacity(skin.opacity.o10) }
        return tokens.color(\.accentPrimary).opacity(skin.opacity.o55 + skin.opacity.o45 * pulse)
    }

    private var bracketColor: Color {
        guard isFocused else { return .clear }
        return tokens.color(\.accentSecondary).opacity(skin.opacity.o85)
    }
}
