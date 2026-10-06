import AinkradAppKit
import SwiftUI

/// The brand chevron. The kit's `AinkradBrandChevron` is the same path; the
/// alias keeps the callers in other areas compiling until their area PRs move
/// onto the kit name, and then it goes.
typealias ChevronMark = AinkradBrandChevron

/// The floating "power core" shown on an empty workspace: the arch ring
/// with the chevron inside, breathing slowly. Reduce Motion freezes the
/// pulse at full glow — driven by Ainkrad's own motion setting, not the
/// macOS system Reduce Motion flag.
struct EmblemView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradSkin) private var skin
    @State private var isBreathing = false

    var body: some View {
        let tokens = environment.themeManager.hostSkin
        let reduceMotion = environment.generalSettingsStore.uiReduceMotion
        let pulse = reduceMotion ? 1.0 : (isBreathing ? 1.0 : 0.72)

        ZStack {
            // Arch ring — brightest at the top, fading toward the base,
            // like the brand mark's halo.
            Circle()
                .stroke(
                    AngularGradient(
                        stops: [
                            .init(color: tokens.color(\.accentPrimary).opacity(skin.opacity.o10), location: 0),
                            .init(color: tokens.color(\.accentSecondary), location: 0.25),
                            .init(color: tokens.color(\.accentPrimary).opacity(skin.opacity.o10), location: 0.5),
                            .init(color: tokens.color(\.accentPrimary).opacity(skin.opacity.o05), location: 0.75),
                            .init(color: tokens.color(\.accentPrimary).opacity(skin.opacity.o10), location: 1),
                        ],
                        center: .center,
                        angle: .degrees(-90)
                    ),
                    lineWidth: 2
                )
                .frame(width: skin.size.s150, height: skin.size.s150)
                .shadow(color: tokens.color(\.accentPrimary).opacity(skin.opacity.o60 * pulse), radius: skin.size.s18)

            AinkradBrandChevron()
                .fill(tokens.color(\.foreground))
                .frame(width: skin.size.s54, height: skin.size.s46)
                .shadow(color: tokens.color(\.accentSecondary).opacity(skin.opacity.o80 * pulse), radius: skin.size.s10)
                .offset(y: 6)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: skin.motion.durations.breathe).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }
}
