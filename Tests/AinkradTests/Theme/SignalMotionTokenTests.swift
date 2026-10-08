import AinkradAppKitUI
import Testing

@testable import Ainkrad
@testable import AinkradHostRuntime

/// The notification surfaces read their motion from the skin. A spring looked
/// up by key resolves to no animation at all when the key is missing, so every
/// theme must carry the keys and today's values — or the dropdown's card-stack
/// expand, the glance row's expand and the bell's hover silently change feel.
@Suite("Signal motion tokens")
@MainActor
struct SignalMotionTokenTests {
    private var skins: [AinkradSkin] {
        neonSchemeIDs.map { NeonSchemes.skin($0) }
    }

    @Test func groupAndRowExpandSpringsKeepTheirFeel() {
        for springs in skins.map(\.motion.springs) {
            #expect(springs["sp32_84"] == AinkradAnimationToken(curve: "spring", response: 0.32, damping: 0.84))
            #expect(springs["sp30_86"] == AinkradAnimationToken(curve: "spring", response: 0.30, damping: 0.86))
        }
    }

    @Test func bellHoverKeepsItsTiming() {
        for durations in skins.map(\.motion.durations) {
            #expect(durations.d0_16 == 0.16)
        }
    }

    @Test func feedScrimKeepsItsDim() {
        for skin in skins {
            #expect(skin.chrome.overlay.backdropOpacity == 0.42)
        }
    }
}
