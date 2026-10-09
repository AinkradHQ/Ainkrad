import AinkradAppKitUI
import Testing

@testable import Ainkrad
@testable import AinkradHostRuntime

/// The setup stage reads its spring from the skin. A spring looked up by key
/// resolves to no animation at all when the key is missing, so the standard
/// skin and every theme must carry `sp42_82` with today's values — or the
/// wizard's step transitions silently snap or change feel.
@Suite("Setup motion tokens")
@MainActor
struct SetupMotionTokenTests {
    private let stageSpring = AinkradAnimationToken(curve: "spring", response: 0.42, damping: 0.82)

    @Test func theStageSpringKeepsItsFeelInTheStandardSkin() {
        #expect(AinkradSkin.standard.motion.springs["sp42_82"] == stageSpring)
    }

    @Test func everyThemeCarriesTheStageSpring() {
        for theme in neonSchemeIDs {
            let springs = NeonSchemes.skin(theme).motion.springs
            #expect(springs["sp42_82"] == stageSpring, "\(theme) lost the stage spring")
        }
    }
}
