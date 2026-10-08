import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad
@testable import AinkradHostRuntime

/// The two-axes data (Neon variant + colour schemes) must compose to exactly
/// the skins today's seven `.theme` files produce.
@Suite("Theme composition parity")
@MainActor
struct ThemeCompositionParityTests {
    @Test("neon.dark + each scheme equals today's theme", arguments: Theme.allCases.map(\.rawValue))
    func composedSkinMatchesToday(id: String) throws {
        let theme = try #require(Theme(rawValue: id))
        let catalog = ThemeCatalog.shared
        let composed = try #require(catalog.compose(themeVariant: "neon.dark", scheme: theme.rawValue))
        #expect(composed.skin == catalog.themeFile(for: theme.rawValue).skin)

        let host = try JSONDecoder().decode(HostSkinSection.self, from: try #require(composed.host))
        #expect(host.language?.id == "neon")
        // Today's file values win over `Theme`'s switch fallback (they disagree for Nord).
        #expect(host.skyProfile == theme.skyProfile)
        #expect(host.iconColorFamily == theme.iconColorFamily)
    }
}
