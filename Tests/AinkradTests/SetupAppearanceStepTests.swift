import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("Setup appearance step")
@MainActor
struct SetupAppearanceStepTests {
    @Test func choicesApplyImmediatelyToTheLiveStores() {
        let t = TestHome.make("appearance")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        SetupAppearance.apply(
            theme: .tokyoNight, accentHex: "FF8800",
            family: .jetBrainsMono, scale: .large,
            icon: .purple, iconAppearance: .dark,
            themeManager: env.themeManager, iconStore: env.appIconStore)

        #expect(env.themeManager.currentTheme == .tokyoNight)
        #expect(env.themeManager.uiFontFamily == .jetBrainsMono)
        #expect(env.themeManager.uiFontScale == .large)
        #expect(env.appIconStore.choice == .purple)
        #expect(env.appIconStore.appearance == .dark)
    }

    /// setTheme clears the accent, so order matters: accent must be applied after.
    @Test func theAccentSurvivesApplyingATheme() {
        let t = TestHome.make("appearance2")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        SetupAppearance.apply(
            theme: .nord, accentHex: "00FFAA",
            family: .exo2, scale: .medium,
            icon: .auto, iconAppearance: .system,
            themeManager: env.themeManager, iconStore: env.appIconStore)

        #expect(env.themeManager.accentColorHex == "00FFAA")
    }
}
