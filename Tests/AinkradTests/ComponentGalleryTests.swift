import AinkradAppKit
import AinkradHostRuntime
import Testing

@testable import Ainkrad

@Suite("Gallery theme injection")
struct ComponentGalleryTests {
    @Test("every Theme maps to a HostThemeTokens the SDK can consume")
    func mapsAllThemes() {
        for theme in Theme.allCases {
            let t = HostThemeTokens(from: theme)  // existing bridge in HostServicesImpl
            #expect(t.themeID == theme.rawValue)
        }
    }
}
