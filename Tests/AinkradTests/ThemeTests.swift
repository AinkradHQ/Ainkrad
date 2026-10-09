import AinkradHostRuntime
import SwiftUI
import Testing

@testable import Ainkrad
@testable import AinkradHostRuntime

@Suite("Theme")
@MainActor
struct ThemeTests {
    @Test("Neon is the only bundled theme, and Neon Blue is its default scheme")
    func neonBlueIsDefault() {
        #expect(NeonSchemes.catalog.languages.map(\.id) == ["neon"])
        #expect(NeonSchemes.catalog.languages.first?.defaultColorScheme == "neonBlue")
    }

    @Test("the brand schemes plus the ported well-known palettes are present")
    func allThemesPresent() {
        #expect(Set(NeonSchemes.catalog.schemes(for: .dark).map(\.id)) == Set(neonSchemeIDs))
        #expect(neonSchemeIDs.count == 7)
    }

    @Test("every scheme resolves to a distinct background token")
    func everyThemeResolves() {
        var backgrounds = Set<Color>()
        for theme in neonSchemeIDs { backgrounds.insert(NeonSchemes.skin(theme).color(\.background)) }
        #expect(backgrounds.count == neonSchemeIDs.count)
    }
}
