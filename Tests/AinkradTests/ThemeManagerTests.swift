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

        // A theme change clears it too.
        manager.setAccentColorHex("FF00AA")
        manager.setTheme("neon")
        #expect(manager.accentColorHex == nil)

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
}
