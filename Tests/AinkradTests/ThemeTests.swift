import AinkradHostRuntime
import SwiftUI
import Testing

@testable import Ainkrad

@Suite("Theme")
struct ThemeTests {
    @Test("neonBlue is the first case (the default theme)")
    func neonBlueIsDefault() {
        #expect(Theme.allCases.first == .neonBlue)
    }

    @Test("the brand themes plus the ported well-known palettes are present")
    func allThemesPresent() {
        #expect(Theme.allCases.count == 7)
        for theme in [Theme.cyberPurple, .dracula, .nord, .tokyoNight, .gruvbox, .solarizedDark] {
            #expect(Theme.allCases.contains(theme))
        }
    }

    @Test("every theme resolves to a distinct background token")
    func everyThemeResolves() {
        var backgrounds = Set<Color>()
        for theme in Theme.allCases { backgrounds.insert(theme.skin.color(\.background)) }
        #expect(backgrounds.count == Theme.allCases.count)
    }
}
