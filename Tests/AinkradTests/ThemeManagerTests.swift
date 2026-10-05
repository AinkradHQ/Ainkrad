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
        #expect(manager.tokens == LegacyDesignTokens.neonBlue)
    }

    @Test("setTheme updates currentTheme and tokens immediately")
    @MainActor
    func setThemeUpdatesState() {
        let manager = makeManager()
        manager.setTheme(.cyberPurple)
        #expect(manager.currentTheme == .cyberPurple)
        #expect(manager.tokens == LegacyDesignTokens.cyberPurple)
    }

    @Test("setTheme persists the selection through SettingsStore")
    @MainActor
    func setThemePersists() {
        let manager = ThemeManager(persistence: store)
        manager.setTheme(.cyberPurple)

        let reloaded = ThemeManager(persistence: store)
        #expect(reloaded.currentTheme == .cyberPurple)
    }

    @Test("setAccentColorHex overrides tokens.accentPrimary; nil restores the theme's accent")
    @MainActor
    func setAccentColorHexOverridesTokens() {
        let manager = makeManager()
        manager.setAccentColorHex("FF00AA")
        #expect(manager.tokens.accentPrimary == Color(hex: "FF00AA"))
        #expect(manager.accentColorHex == "FF00AA")

        manager.setAccentColorHex(nil)
        #expect(manager.tokens == LegacyDesignTokens.neonBlue)
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
        #expect(reloaded.tokens.accentPrimary == Color(hex: "00FF00"))
    }

    @Test("changing theme clears a custom accent so the accent follows the theme")
    @MainActor
    func setThemeClearsAccentOverride() {
        let manager = makeManager()
        manager.setAccentColorHex("FF00AA")
        #expect(manager.accentColorHex == "FF00AA")

        manager.setTheme(.gruvbox)

        #expect(manager.accentColorHex == nil)
        #expect(manager.tokens.accentPrimary == LegacyDesignTokens.gruvbox.accentPrimary)

        // And it's cleared in persistence too.
        let reloaded = makeManager()
        #expect(reloaded.accentColorHex == nil)
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
