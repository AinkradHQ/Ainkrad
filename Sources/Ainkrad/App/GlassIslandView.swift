// design-lint: allow-file frame-literal,padding-literal,spacing-literal brand composition metrics, scaled by the view size
import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// The Liquid Glass home (`host.language.island: glass`): the Setup brand mark
/// — chevron, crystal, drifting linked sparks and halo, lit even though the
/// theme clears its bloom — above the AINKRAD wordmark and its tagline.
///
/// The wordmark is three template layers traced from the brand artwork
/// (`Designs/island-layers-ai/logo.png`, `slogan.png`): the letters take the
/// foreground colour, the crystals in the two As and the tagline take the
/// accent, so the home follows the colour scheme.
///
/// Motion: the sparks drift on their own (the mark's timeline), and the whole
/// brand follows the pointer as ONE rigid piece — Ahmed: it moves as it is,
/// never stretching or bending. Still under Reduce Motion or when not visible.
struct GlassIslandView: View {
    var isVisible: Bool = true

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @Environment(\.ainkradSkin) private var skin
    /// Pointer position in the view, -1...1 on each axis; zero at rest.
    @State private var pointer: CGPoint = .zero

    private var animates: Bool { isVisible && !reduceMotion }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let unit = min(size.width / 860, size.height / 574)
            let tokens = environment.themeManager.hostSkin
            VStack(spacing: 18 * unit) {
                // The mark's box includes its halo and spark field; pull the
                // wordmark up into that empty lower edge.
                SetupBrandMark(
                    tokens: tokens, reduceMotion: !animates, style: .hero(diameter: 300 * unit), forcesGlow: true)
                    .padding(.bottom, -44 * unit)
                wordmark(tokens: tokens, unit: unit)
                Image("Wordmark-Tagline")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 324 * unit)
                    .foregroundStyle(tokens.color(\.accentSecondary))
            }
            // One rigid piece: the whole brand follows the pointer together,
            // so nothing in it shifts against anything else.
            .offset(follow(unit: unit))
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard animates else { return }
                switch phase {
                case .active(let location):
                    pointer = CGPoint(
                        x: max(-1, min(1, location.x / max(size.width, 1) * 2 - 1)),
                        y: max(-1, min(1, location.y / max(size.height, 1) * 2 - 1)))
                case .ended:
                    pointer = .zero
                }
            }
            .animation(skin.animation(skin.motion.present), value: pointer)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ainkrad. Build, focus, elevate.")
    }

    /// The letters in the foreground colour, the crystals in the accent.
    private func wordmark(tokens: AinkradSkin, unit: CGFloat) -> some View {
        ZStack {
            Image("Wordmark-Letters").resizable().scaledToFit()
                .foregroundStyle(tokens.color(\.foreground))
            Image("Wordmark-Diamonds").resizable().scaledToFit()
                .foregroundStyle(tokens.color(\.accentSecondary))
        }
        .frame(width: 423 * unit)
    }

    /// How far the brand follows the pointer.
    private func follow(unit: CGFloat) -> CGSize {
        let reach = 14 * unit
        return CGSize(width: pointer.x * reach, height: pointer.y * reach * 0.6)
    }
}
