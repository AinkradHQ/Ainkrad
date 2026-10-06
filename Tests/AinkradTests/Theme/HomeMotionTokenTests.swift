import AinkradAppKitUI
import Testing

@testable import Ainkrad
@testable import AinkradHostRuntime

/// The Home surface reads its motion from the skin. A spring looked up by key
/// resolves to no animation at all when the key is missing, so every theme
/// must carry the keys and today's values — or the carousel, the focus pop
/// and the emblem's breathing silently change feel.
@Suite("Home motion tokens")
struct HomeMotionTokenTests {
    private var skins: [AinkradSkin] {
        Theme.allCases.map { ThemeCatalog.shared.themeFile(for: $0.rawValue).skin }
    }

    @Test func carouselAndFocusPopSpringsKeepTheirFeel() {
        for springs in skins.map(\.motion.springs) {
            #expect(springs["sp42_88"] == AinkradAnimationToken(curve: "spring", response: 0.42, damping: 0.88))
            #expect(springs["sp34_80"] == AinkradAnimationToken(curve: "spring", response: 0.34, damping: 0.80))
        }
    }

    @Test func homeDurationsKeepTheirTiming() {
        for durations in skins.map(\.motion.durations) {
            #expect(durations.d0_12 == 0.12)
            #expect(durations.d0_16 == 0.16)
            #expect(durations.d0_18 == 0.18)
            #expect(durations.breathe == 3.2)
        }
    }

    @Test func overlayScrimKeepsItsDim() {
        for skin in skins {
            #expect(skin.chrome.overlay.backdropOpacity == 0.42)
        }
    }
}
