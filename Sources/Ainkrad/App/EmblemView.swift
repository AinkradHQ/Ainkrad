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
    @State private var isBreathing = false

    var body: some View {
        let tokens = environment.themeManager.tokens
        let reduceMotion = environment.generalSettingsStore.uiReduceMotion
        let pulse = reduceMotion ? 1.0 : (isBreathing ? 1.0 : 0.72)

        ZStack {
            // Arch ring — brightest at the top, fading toward the base,
            // like the brand mark's halo.
            Circle()
                .stroke(
                    AngularGradient(
                        stops: [
                            .init(color: tokens.accentPrimary.opacity(0.1), location: 0),
                            .init(color: tokens.accentSecondary, location: 0.25),
                            .init(color: tokens.accentPrimary.opacity(0.1), location: 0.5),
                            .init(color: tokens.accentPrimary.opacity(0.05), location: 0.75),
                            .init(color: tokens.accentPrimary.opacity(0.1), location: 1),
                        ],
                        center: .center,
                        angle: .degrees(-90)
                    ),
                    lineWidth: 2
                )
                .frame(width: 150, height: 150)
                .shadow(color: tokens.accentPrimary.opacity(0.6 * pulse), radius: 18)

            ChevronMark()
                .fill(tokens.foreground)
                .frame(width: 54, height: 46)
                .shadow(color: tokens.accentSecondary.opacity(0.8 * pulse), radius: 10)
                .offset(y: 6)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }
}
