import AinkradHostRuntime
import Foundation
import SwiftUI
import Testing

@testable import Ainkrad

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
        #expect(manager.currentTheme == .neonBlue)
        #expect(LegacyPalettes.hexes(manager.hostSkin) == LegacyPalettes.table[.neonBlue])
    }

    @Test("setTheme updates currentTheme and the skins immediately")
    @MainActor
    func setThemeUpdatesState() {
        let manager = makeManager()
        manager.setTheme(.cyberPurple)
        #expect(manager.currentTheme == .cyberPurple)
        #expect(LegacyPalettes.hexes(manager.skin) == LegacyPalettes.table[.cyberPurple])
        #expect(LegacyPalettes.hexes(manager.hostSkin) == LegacyPalettes.table[.cyberPurple])
    }

    @Test("setTheme persists the selection through SettingsStore")
    @MainActor
    func setThemePersists() {
        let manager = ThemeManager(persistence: store)
        manager.setTheme(.cyberPurple)

        let reloaded = ThemeManager(persistence: store)
        #expect(reloaded.currentTheme == .cyberPurple)
    }

    @Test("setAccentColorHex overrides hostSkin's accentPrimary only; nil restores the theme's accent")
    @MainActor
    func setAccentColorHexOverridesHostSkin() {
        let manager = makeManager()
        manager.setAccentColorHex("FF00AA")
        #expect(manager.hostSkin.color(\.accentPrimary).hexString == "FF00AA")
        // R2: the injected skin never carries the custom accent.
        #expect(manager.skin.palette == manager.currentTheme.skin.palette)
        var expected = LegacyPalettes.table[.neonBlue] ?? []
        expected[3] = "FF00AA"
        #expect(LegacyPalettes.hexes(manager.hostSkin) == expected)
        #expect(manager.accentColorHex == "FF00AA")

        manager.setAccentColorHex(nil)
        #expect(LegacyPalettes.hexes(manager.hostSkin) == LegacyPalettes.table[.neonBlue])
        #expect(manager.accentColorHex == nil)
    }

    @Test("setAccentColorHex persists through SettingsStore and preserves the theme")
    @MainActor
    func setAccentColorHexPersists() {
        let manager = ThemeManager(persistence: store)
        manager.setTheme(.cyberPurple)
        manager.setAccentColorHex("00FF00")

        let reloaded = ThemeManager(persistence: store)
        #expect(reloaded.currentTheme == .cyberPurple)
        #expect(reloaded.accentColorHex == "00FF00")
        #expect(reloaded.hostSkin.color(\.accentPrimary).hexString == "00FF00")
    }

    @Test("changing theme clears a custom accent so the accent follows the theme")
    @MainActor
    func setThemeClearsAccentOverride() {
        let manager = makeManager()
        manager.setAccentColorHex("FF00AA")
        #expect(manager.accentColorHex == "FF00AA")

        manager.setTheme(.gruvbox)

        #expect(manager.accentColorHex == nil)
        #expect(manager.hostSkin.color(\.accentPrimary).hexString == LegacyPalettes.table[.gruvbox]?[3])

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
