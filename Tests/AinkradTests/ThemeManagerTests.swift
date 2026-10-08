import AinkradAppKit
import AinkradHostRuntime
import Foundation
import SwiftUI
import Testing

@testable import Ainkrad
@testable import AinkradHostRuntime

@Suite("ThemeManager")
final class ThemeManagerTests {
    let store = InMemoryPersistenceStore()

    @MainActor
    private func makeManager() -> ThemeManager {
        ThemeManager(persistence: store)
    }

    @Test("defaults to Neon Blue with no prior saved settings")
    @MainActor
    func defaultsToNeonBlue() {
        let manager = makeManager()
        #expect(manager.currentThemeID == "neon")
        #expect(manager.skin.id == "neonBlue")
        #expect(manager.colorSchemeID(for: .dark) == nil)
        #expect(LegacyPalettes.hexes(manager.hostSkin) == LegacyPalettes.table["neonBlue"])
    }

    @Test("setColorScheme updates the skins immediately")
    @MainActor
    func setColorSchemeUpdatesState() {
        let manager = makeManager()
        manager.setColorScheme("cyberPurple", for: .dark)
        #expect(manager.colorSchemeID(for: .dark) == "cyberPurple")
        #expect(LegacyPalettes.hexes(manager.skin) == LegacyPalettes.table["cyberPurple"])
        #expect(LegacyPalettes.hexes(manager.hostSkin) == LegacyPalettes.table["cyberPurple"])
    }

    @Test("setTheme and setColorScheme persist the selection through SettingsStore")
    @MainActor
    func setThemePersists() {
        let manager = ThemeManager(persistence: store)
        manager.setTheme("neon")
        manager.setColorScheme("cyberPurple", for: .dark)

        let reloaded = ThemeManager(persistence: store)
        #expect(reloaded.currentThemeID == "neon")
        #expect(reloaded.colorSchemeID(for: .dark) == "cyberPurple")
        #expect(reloaded.skin.id == "cyberPurple")
    }

    @Test("each scheme composes to the E0.2 skin, and its tokens carry the old theme id")
    @MainActor
    func everySchemeMatchesComposition() {
        let manager = makeManager()
        for id in neonSchemeIDs {
            manager.setColorScheme(id, for: .dark)
            #expect(manager.skin == NeonSchemes.skin(id), "\(id)")
            #expect(manager.skyProfile == NeonSchemes.host(id).skyProfile, "\(id)")
            #expect(manager.iconColorFamily == NeonSchemes.host(id).iconColorFamily, "\(id)")
            #expect(manager.composedKey == "neon.dark|\(id)")
            #expect(HostThemeTokens(skin: manager.skin).themeID == id)
        }
    }

    @Test("unknown theme and scheme ids resolve to Neon defaults but stay stored")
    @MainActor
    func unknownIDsFallBackWithoutRewriting() {
        store.save(GlobalSettings(theme: "glass", colorSchemeDark: "missing"))
        let manager = makeManager()
        #expect(manager.currentThemeID == "glass")
        #expect(manager.skin.id == "neonBlue")
        #expect(manager.composedKey == "neon.dark|neonBlue")
        let saved = store.load(GlobalSettings.self)
        #expect(saved?.theme == "glass")
        #expect(saved?.colorSchemeDark == "missing")
    }

    @Test("an unknown theme still honours a stored scheme that exists")
    @MainActor
    func unknownThemeKeepsKnownScheme() {
        store.save(GlobalSettings(theme: "glass", colorSchemeDark: "nord"))
        #expect(makeManager().skin.id == "nord")
    }

    @Test("a nil scheme clears the choice back to the theme default")
    @MainActor
    func nilSchemeRestoresDefault() {
        let manager = makeManager()
        manager.setColorScheme("gruvbox", for: .dark)
        manager.setColorScheme(nil, for: .dark)
        #expect(manager.colorSchemeID(for: .dark) == nil)
        #expect(manager.skin.id == manager.defaultColorSchemeID)
        #expect(store.load(GlobalSettings.self)?.colorSchemeDark == nil)
    }

    @Test("the picker lists the seven bundled schemes in today's order")
    @MainActor
    func pickerOrder() {
        #expect(makeManager().colorSchemes.map(\.id) == neonSchemeIDs)
    }

    @Test("setAccentColorHex overrides hostSkin's accentPrimary only; nil restores the theme's accent")
    @MainActor
    func setAccentColorHexOverridesHostSkin() {
        let manager = makeManager()
        manager.setAccentColorHex("FF00AA")
        #expect(manager.hostSkin.color(\.accentPrimary).hexString == "FF00AA")
        // R2: the injected skin never carries the custom accent.
        #expect(manager.skin.palette == NeonSchemes.skin("neonBlue").palette)
        var expected = LegacyPalettes.table["neonBlue"] ?? []
        expected[3] = "FF00AA"
        #expect(LegacyPalettes.hexes(manager.hostSkin) == expected)
        #expect(manager.accentColorHex == "FF00AA")

        manager.setAccentColorHex(nil)
        #expect(LegacyPalettes.hexes(manager.hostSkin) == LegacyPalettes.table["neonBlue"])
        #expect(manager.accentColorHex == nil)
    }

    @Test("setAccentColorHex persists through SettingsStore and preserves the theme")
    @MainActor
    func setAccentColorHexPersists() {
        let manager = ThemeManager(persistence: store)
        manager.setColorScheme("cyberPurple", for: .dark)
        manager.setAccentColorHex("00FF00")

        let reloaded = ThemeManager(persistence: store)
        #expect(reloaded.skin.id == "cyberPurple")
        #expect(reloaded.accentColorHex == "00FF00")
        #expect(reloaded.hostSkin.color(\.accentPrimary).hexString == "00FF00")
    }

    @Test("changing theme clears a custom accent so the accent follows the theme")
    @MainActor
    func setThemeClearsAccentOverride() {
        let manager = makeManager()
        manager.setAccentColorHex("FF00AA")
        #expect(manager.accentColorHex == "FF00AA")

        manager.setColorScheme("gruvbox", for: .dark)

        #expect(manager.accentColorHex == nil)
        #expect(manager.hostSkin.color(\.accentPrimary).hexString == LegacyPalettes.table["gruvbox"]?[3])

        // A change to another theme clears it too: `setThemeAdoptsFontFamily`
        // (the bundle has only Neon, and re-picking it is a no-op).

        // And it's cleared in persistence too.
        let reloaded = makeManager()
        #expect(reloaded.accentColorHex == nil)
    }

    @Test("setAccentColor stores the picked colour as its hex")
    @MainActor
    func setAccentColorStoresHex() {
        let manager = makeManager()
        manager.setAccentColor(Color(.sRGB, red: 1, green: 0, blue: 0))
        #expect(manager.accentColorHex == "FF0000")
        #expect(manager.hostSkin.color(\.accentPrimary).hexString == "FF0000")
    }

    @Test("setFontScale and setFontFamily update state and persist")
    @MainActor
    func setFontScaleAndFamilyPersist() {
        let manager = ThemeManager(persistence: store)
        manager.setFontScale(.large)
        manager.setFontFamily(.jetBrainsMono)
        #expect(manager.uiFontScale == .large)
        #expect(manager.uiFontFamily == .jetBrainsMono)

        let reloaded = ThemeManager(persistence: store)
        #expect(reloaded.uiFontScale == .large)
        #expect(reloaded.uiFontFamily == .jetBrainsMono)
    }

    // MARK: - E0.5: switching theme

    @MainActor
    private func fixtureManager() -> ThemeManager {
        ThemeManager(
            persistence: store,
            catalog: ThemeCatalog(bundle: .main, userRoots: [ThemeFixtures.tempDir(ThemeFixtures.lightVariant)]))
    }

    @Test("setTheme keeps an explicit scheme that is still installed and drops one that is not")
    @MainActor
    func setThemeKeepsInstalledSchemes() {
        defer { AinkradFont.configure(scale: 1, family: .exo2) }
        let manager = fixtureManager()
        manager.setColorScheme("gruvbox", for: .dark)
        manager.setColorScheme("paper", for: .light)
        manager.setTheme("glassy")
        #expect(manager.colorSchemeID(for: .dark) == "gruvbox")
        #expect(manager.colorSchemeID(for: .light) == "paper")
        #expect(manager.skin.id == "gruvbox")

        store.save(GlobalSettings(theme: "neon", colorSchemeDark: "uninstalled", colorSchemeLight: "gone"))
        let stale = fixtureManager()
        stale.setTheme("glassy")
        #expect(stale.colorSchemeID(for: .dark) == nil)
        #expect(stale.colorSchemeID(for: .light) == nil)
        #expect(stale.skin.id == "nord")  // glassy's own dark default
        let saved = store.load(GlobalSettings.self)
        #expect(saved?.colorSchemeDark == nil)
        #expect(saved?.colorSchemeLight == nil)
    }

    @Test("setTheme adopts the theme's font family and resets the accent (R9)")
    @MainActor
    func setThemeAdoptsFontFamily() {
        defer { AinkradFont.configure(scale: 1, family: .exo2) }
        let manager = fixtureManager()
        manager.setFontFamily(.jetBrainsMono)
        manager.setAccentColorHex("FF00AA")
        manager.setTheme("glassy")
        #expect(manager.uiFontFamily == .system)
        #expect(manager.accentColorHex == nil)
        #expect(store.load(GlobalSettings.self)?.uiFontFamily == .system)

        manager.setTheme("neon")
        #expect(manager.uiFontFamily == .exo2)

        // An unknown family is logged and the current one kept.
        manager.setFontFamily(.jetBrainsMono)
        manager.setTheme("odd")
        #expect(manager.uiFontFamily == .jetBrainsMono)
        // An uninstalled theme has no family to adopt.
        manager.setTheme("missing")
        #expect(manager.uiFontFamily == .jetBrainsMono)
    }

    @Test("re-picking the current theme keeps the user's typeface and accent")
    @MainActor
    func samethemeIsANoOp() {
        defer { AinkradFont.configure(scale: 1, family: .exo2) }
        let manager = fixtureManager()
        manager.setFontFamily(.jetBrainsMono)
        manager.setAccentColorHex("FF00AA")
        manager.setTheme(manager.currentThemeID)
        #expect(manager.uiFontFamily == .jetBrainsMono)
        #expect(manager.accentColorHex == "FF00AA")
    }

    @Test("themes, the active theme and per-appearance defaults come from the catalog")
    @MainActor
    func themeListAndDefaults() {
        let manager = fixtureManager()
        #expect(manager.themes.map(\.id) == ["glassy", "neon", "odd"])
        #expect(manager.activeThemeID == "neon")
        #expect(manager.defaultColorSchemeID(for: .dark) == "neonBlue")
        #expect(manager.defaultColorSchemeID(for: .light) == nil)
        #expect(manager.colorSchemes(for: .light).map(\.id) == ["paper"])

        store.save(GlobalSettings(theme: "glassy"))
        let glassy = fixtureManager()
        #expect(glassy.activeThemeID == "glassy")
        #expect(glassy.defaultColorSchemeID(for: .light) == "paper")
        #expect(glassy.defaultColorSchemeID(for: .dark) == "nord")

        store.save(GlobalSettings(theme: "uninstalled"))
        #expect(fixtureManager().activeThemeID == "neon")
    }
}
