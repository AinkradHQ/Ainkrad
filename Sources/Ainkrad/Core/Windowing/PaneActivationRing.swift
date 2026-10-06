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
    let tokens: DesignTokens

    @Environment(\.ainkradReduceMotion) private var reduceMotion
    /// 1 at the instant of activation, easing to 0. Drives both the border's
    /// brightness and its width, so the flare reads as light rather than as the
    /// frame changing size.
    @State private var pulse: Double = 0

    var body: some View {
        ZStack {
            ChamferShape(cut: AinkradRadius.md)
                .strokeBorder(borderColor, lineWidth: 1 + pulse * 0.6)

            TargetingBrackets(length: 10)
                .stroke(bracketColor, lineWidth: 1.5)
                .padding(-2)
        }
        .onChange(of: isFocused) { _, focused in
            guard focused, !reduceMotion else { return }
            // Set the start value, then animate to rest on the next tick, so
            // the flare actually renders at full strength before it decays.
            pulse = 1
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.32)) { pulse = 0 }
            }
        }
    }

    private var borderColor: Color {
        guard isFocused else { return tokens.foreground.opacity(0.1) }
        return tokens.accentPrimary.opacity(0.55 + 0.45 * pulse)
    }

    private var bracketColor: Color {
        guard isFocused else { return .clear }
        return tokens.accentSecondary.opacity(0.85)
    }
}
