import AinkradAppKitUI
import Foundation

@testable import AinkradHostRuntime

/// The seven bundled colour schemes under Neon — the old `Theme` raw values,
/// in the old order. `ThemeCatalogTests` checks the bundle ships exactly these.
let neonSchemeIDs = ["neonBlue", "cyberPurple", "dracula", "nord", "tokyoNight", "gruvbox", "solarizedDark"]

/// Composed Neon skins for tests, from one bundle-only catalog. Main actor:
/// composing a giant skin on a 512 KiB test worker overflows its stack.
@MainActor
enum NeonSchemes {
    static let catalog = ThemeCatalog(bundle: .main)

    static func file(_ schemeID: String) -> AinkradThemeFile {
        guard let file = catalog.compose(themeVariant: "neon.dark", scheme: schemeID) else {
            preconditionFailure("neon.dark + \(schemeID) does not compose")
        }
        return file
    }

    static func skin(_ schemeID: String) -> AinkradSkin { file(schemeID).skin }

    static func host(_ schemeID: String) -> HostSkinSection {
        guard let data = file(schemeID).host, let host = try? JSONDecoder().decode(HostSkinSection.self, from: data)
        else { preconditionFailure("\(schemeID) has no host section") }
        return host
    }
}
