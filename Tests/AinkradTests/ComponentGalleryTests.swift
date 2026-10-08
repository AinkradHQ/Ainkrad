import AinkradAppKit
import AinkradHostRuntime
import Testing

@testable import Ainkrad

@Suite("Gallery theme injection")
@MainActor
struct ComponentGalleryTests {
    @Test("every gallery scheme maps to a HostThemeTokens the SDK can consume")
    func mapsAllThemes() {
        for theme in neonSchemeIDs {
            let t = HostThemeTokens(skin: ComponentGalleryView.skin(forScheme: theme))
            #expect(t.themeID == theme)
        }
    }
}
