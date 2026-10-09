import AinkradAppKit
import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad
@testable import AinkradHostRuntime

/// The two-axes data (Neon variant + colour schemes) composes to the skins the
/// seven old `.theme` files produced (`default.theme` + the scheme's colours,
/// captured before those files were deleted in E0.3).
@Suite("Theme composition parity")
@MainActor
struct ThemeCompositionParityTests {
    /// The sky profile and icon family the old `.theme` files carried, captured
    /// from them before deletion (Neon Blue: `Theme`'s fallback, as
    /// `default.theme` has no host block).
    private static let oldHost: [String: (SkyProfile, AppIconColor)] = [
        "neonBlue": (SkyProfile(1.00, 0.90, 0.90, 1.00, 1.00), .blue),
        "cyberPurple": (SkyProfile(1.25, 0.90, 0.80, 1.10, 1.00), .purple),
        "dracula": (SkyProfile(1.20, 0.85, 0.85, 1.15, 1.00), .purple),
        "nord": (SkyProfile(0.80, 1.10, 1.20, 0.90, 1.00), .blue),
        "tokyoNight": (SkyProfile(1.10, 0.85, 1.25, 1.00, 1.00), .blue),
        "gruvbox": (SkyProfile(0.90, 1.25, 0.80, 1.10, 1.00), .blue),
        "solarizedDark": (SkyProfile(0.85, 1.00, 1.25, 0.90, 1.00), .blue),
    ]

    @Test("neon.dark + each scheme equals the old theme", arguments: neonSchemeIDs)
    func composedSkinMatchesToday(id: String) throws {
        let catalog = NeonSchemes.catalog
        let composed = try #require(catalog.compose(themeVariant: "neon.dark", scheme: id))
        let scheme = try #require(catalog.schemes(for: .dark).first { $0.id == id })

        // Identity: the composed skin is the scheme, named as the old theme.
        #expect(composed.skin.id == id)
        #expect(composed.skin.name == scheme.name)
        #expect(HostThemeTokens(skin: composed.skin).themeID == id)

        // Colours: the old theme's palette, as captured in `LegacyPalettes`.
        #expect(LegacyPalettes.hexes(composed.skin) == LegacyPalettes.table[id])

        // Everything that is not colour comes from default.theme unchanged.
        let base = try #require(catalog.loadedThemes["neonBlue"]?.themeFile.skin)
        #expect(composed.skin.spacing == base.spacing)
        #expect(composed.skin.motion == base.motion)
        #expect(composed.skin.shape == base.shape)
        #expect(composed.skin.size == base.size)

        let host = try JSONDecoder().decode(HostSkinSection.self, from: try #require(composed.host))
        let old = try #require(Self.oldHost[id])
        #expect(host.language?.id == "neon")
        #expect(host.skyProfile == old.0)
        #expect(host.iconColorFamily == old.1)
    }
}
