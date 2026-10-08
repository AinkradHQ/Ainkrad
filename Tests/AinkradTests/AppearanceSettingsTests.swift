import AinkradAppKitContract
import AinkradHostRuntime
import Foundation
import SwiftUI
import Testing

@testable import Ainkrad

/// Settings → Appearance → Theme: Theme + per-appearance colour scheme
/// selects and the Theme files row (E0.5).
@Suite("Appearance settings")
@MainActor
struct AppearanceSettingsTests {
    private let group = SettingsPath(["workspace", "appearance", "theme"])

    /// A bootstrapped environment whose `<Home>/Config/Themes` holds `files`.
    private func environment(_ files: [String: String]) -> (AppEnvironment, () -> Void) {
        let t = TestHome.make("appearance-settings")
        ThemeFixtures.write(files, to: t.home.shared(.config).appendingPathComponent("Themes", isDirectory: true))
        return (AppEnvironment.bootstrap(home: t.home, defaults: t.defaults), t.cleanup)
    }

    private func fields(_ env: AppEnvironment) -> [String: SettingsField] {
        Dictionary(
            uniqueKeysWithValues: HostSettingsCatalog.themeFields(env, group: group).map { ($0.label, $0) })
    }

    private func select(_ field: SettingsField?) -> (ids: [String], selection: Binding<String>)? {
        guard case .select(let options, let selection) = field?.kind else { return nil }
        return (options.map(\.id), selection)
    }

    @Test("under Neon: Theme and Dark colour scheme, no Light row, files all loaded")
    func neonRows() throws {
        defer { AinkradFont.configure(scale: 1, family: .exo2) }
        let (env, cleanup) = environment([:])
        defer { cleanup() }
        let rows = fields(env)
        #expect(rows["Light colour scheme"] == nil)
        let theme = try #require(select(rows["Theme"]))
        #expect(theme.ids == ["neon"])
        #expect(theme.selection.wrappedValue == "neon")
        let dark = try #require(select(rows["Dark colour scheme"]))
        #expect(dark.ids == neonSchemeIDs)
        #expect(dark.selection.wrappedValue == "neonBlue")
        #expect(rows["Dark colour scheme"]?.defaultDescription == "Theme default (Neon Blue)")
        guard case .action(let title, _) = rows["Theme files"]?.kind else {
            Issue.record("Theme files is not an action")
            return
        }
        #expect(title == "All loaded")
    }

    @Test("the selects go through ThemeManager; reset returns to the theme default")
    func selectsWriteThroughThemeManager() throws {
        defer { AinkradFont.configure(scale: 1, family: .exo2) }
        let (env, cleanup) = environment([:])
        defer { cleanup() }
        let manager = env.themeManager
        let dark = try #require(fields(env)["Dark colour scheme"])
        try #require(select(dark)).selection.wrappedValue = "nord"
        #expect(manager.colorSchemeID(for: .dark) == "nord")
        #expect(manager.skin.id == "nord")
        #expect(dark.isModified())
        dark.reset?()
        #expect(manager.colorSchemeID(for: .dark) == nil)
        #expect(manager.skin.id == "neonBlue")
    }

    @Test("a theme with a light variant shows the Light colour scheme row")
    func lightRowForLightVariant() throws {
        defer { AinkradFont.configure(scale: 1, family: .exo2) }
        let (env, cleanup) = environment(ThemeFixtures.lightVariant)
        defer { cleanup() }
        #expect(fields(env)["Light colour scheme"] == nil)  // still Neon

        try #require(select(fields(env)["Theme"])).selection.wrappedValue = "glassy"
        #expect(env.themeManager.currentThemeID == "glassy")
        #expect(env.themeManager.uiFontFamily == .system)

        let rows = fields(env)
        let light = try #require(select(rows["Light colour scheme"]))
        #expect(light.ids == ["paper"])
        #expect(light.selection.wrappedValue == "paper")
        #expect(rows["Light colour scheme"]?.defaultDescription == "Theme default (Paper)")
        #expect(rows["Dark colour scheme"]?.defaultDescription == "Theme default (Nord)")
        #expect(rows["Theme"]?.isModified() == true)
        rows["Theme"]?.reset?()
        #expect(env.themeManager.currentThemeID == "neon")
        #expect(fields(env)["Light colour scheme"] == nil)
    }

    @Test("load problems are counted on the Theme files row, whose action opens the modal")
    func themeFilesRowCountsIssues() {
        let (env, cleanup) = environment(ThemeFixtures.broken)
        defer { cleanup() }
        guard case .action(let title, let handler) = fields(env)["Theme files"]?.kind else {
            Issue.record("Theme files is not an action")
            return
        }
        #expect(title == "2 files could not load")
        #expect(env.themeManager.catalogIssues.count == 2)
        #expect(!env.settingsDrafts.showsThemeFiles)
        handler()
        #expect(env.settingsDrafts.showsThemeFiles)
    }

    @Test("a warning is listed but not counted as a file that could not load")
    func themeFilesRowSeparatesWarnings() {
        for (files, title) in [
            (ThemeFixtures.warned, "All loaded, 1 warning"),
            (ThemeFixtures.broken.merging(ThemeFixtures.warned) { $1 }, "2 files could not load"),
        ] {
            let (env, cleanup) = environment(files)
            defer { cleanup() }
            guard case .action(let shown, _) = fields(env)["Theme files"]?.kind else {
                Issue.record("Theme files is not an action")
                return
            }
            #expect(shown == title)
            #expect(env.themeManager.catalogIssues.contains { $0.contains("warning: ") })
        }
    }

    @Test("search keywords cover theme, colour, color scheme, palette, light and dark")
    func keywords() {
        let (env, cleanup) = environment([:])
        defer { cleanup() }
        let words = Set(HostSettingsCatalog.themeFields(env, group: group).flatMap(\.keywords))
        for word in ["theme", "colour", "color scheme", "palette", "light", "dark"] {
            #expect(words.contains(word), "\(word)")
        }
    }
}
