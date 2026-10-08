import AinkradAppKit
import CoreGraphics
import Testing

@testable import Ainkrad
@testable import AinkradHostRuntime

@Suite("OverlayChrome")
@MainActor
struct OverlayChromeTests {
    @Test("chrome corner radius derives from the shared panel radius")
    func cornerRadiusUsesScale() {
        #expect(OverlayChrome.cornerRadius == AinkradRadius.panel)
        #expect(OverlayChrome.cornerRadius == 14)  // behavior-preserving
    }

    @Test("the scrim opacity keeps today's value")
    func backdropOpacityIsUnchanged() {
        #expect(OverlayChrome.backdropOpacity == 0.42)
    }

    /// The statics read `AinkradSkin.standard`; this proves that equals the
    /// skin each bundled theme actually loads.
    @Test("the statics equal every bundled theme's skin")
    func staticsMatchEveryTheme() {
        for theme in neonSchemeIDs {
            let skin = NeonSchemes.skin(theme)
            #expect(CGFloat(skin.radius.panel) == OverlayChrome.cornerRadius, "\(theme)")
            #expect(skin.chrome.overlay.backdropOpacity == OverlayChrome.backdropOpacity, "\(theme)")
        }
    }

    @Test("the panel edge keeps today's alphas and width")
    func panelEdgeTokensAreUnchanged() {
        let skin = AinkradSkin.standard
        #expect(skin.opacity.o55 == 0.55)
        #expect(skin.opacity.o28 == 0.28)
        #expect(skin.chrome.overlay.edgeWidth == 1)
    }
}

@Suite("NeonAppTile tokens")
struct NeonAppTileTokenTests {
    @Test("bloom, badge and badge motion keep today's values")
    func tokensMatchTheReplacedLiterals() throws {
        let skin = AinkradSkin.standard
        #expect(skin.opacity.o35 == 0.35)
        #expect(skin.opacity.o16 == 0.16)
        #expect(skin.opacity.o60 == 0.60)
        #expect(skin.cut.r0_10 == 0.10)
        let spring = try #require(skin.motion.springs["sp30_70"])
        #expect(spring.curve == "spring")
        #expect(spring.response == 0.30)
        #expect(spring.damping == 0.70)
    }
}
