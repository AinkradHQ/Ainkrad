import AinkradAppKit
import AinkradHostRuntime
import Foundation
import SwiftUI
import Testing

@testable import Ainkrad
@testable import AinkradHostRuntime

@Suite("HostServices theme")
@MainActor
struct HostServicesThemeTests {
    private func makeHost(catalog: ThemeCatalog = ThemeCatalog()) -> (HostServicesImpl, ThemeManager) {
        let persistence = InMemoryPersistenceStore()
        let tm = ThemeManager(persistence: persistence, catalog: catalog)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let host = HostServicesImpl(
            appID: "t", dataRootURL: root,
            secretStore: InMemorySecretStore(), themeManager: tm,
            hub: AgentContextRegistryHub(), actionHub: AgentActionRegistryHub(),
            launchHub: PluginLaunchHub(), signalHub: SignalEmitterHub(),
            declaredPresentation: .pane,
            appAppearanceStore: AppAppearanceStore(persistence: InMemoryPersistenceStore()))
        return (host, tm)
    }

    @Test("theme starts on the active theme")
    func startsOnActive() {
        let (host, _) = makeHost()
        #expect(host.theme.tokens.themeID == "neonBlue")
    }

    @Test("theme follows repeated theme changes (proves the observation re-arms)")
    func followsChange() async {
        let (host, tm) = makeHost()

        tm.setColorScheme("dracula", for: .dark)
        for _ in 0..<20 where host.theme.tokens.themeID != "dracula" { await Task.yield() }
        #expect(host.theme.tokens.themeID == "dracula")
        #expect(host.theme.tokens.background.hexString == "1A1B23")

        // A second change must also propagate — guards the self-re-arm.
        tm.setColorScheme("nord", for: .dark)
        for _ in 0..<20 where host.theme.tokens.themeID != "nord" { await Task.yield() }
        #expect(host.theme.tokens.themeID == "nord")
    }

    @Test("a scheme-only switch republishes tokens and status colours")
    func schemeOnlySwitchUpdatesStatusColors() async {
        let (host, tm) = makeHost()
        let before = host.theme.statusColors
        tm.setColorScheme("gruvbox", for: .dark)
        for _ in 0..<20 where host.theme.tokens.themeID != "gruvbox" { await Task.yield() }
        #expect(tm.currentThemeID == "neon")
        #expect(host.theme.tokens.themeID == "gruvbox")
        #expect(host.theme.statusColors == HostStatusColors(from: tm.skin))
        #expect(host.theme.statusColors != before)
    }

    @Test("a theme-only switch republishes tokens and status colours")
    func themeOnlySwitchUpdates() async throws {
        // A second language whose default scheme differs from Neon's; no scheme is stored,
        // so switching the theme alone changes the composed skin.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try #"""
        {"schemaVersion": 1, "id": "other.dark", "name": "Other", "base": "neonBlue",
         "host": {"language": {"id": "other", "name": "Other", "appearance": "dark", "defaultColorScheme": "otherScheme"}}}
        """#.write(to: root.appendingPathComponent("other-dark.theme"), atomically: true, encoding: .utf8)
        try ##"""
        {"schemaVersion": 1, "id": "otherScheme", "name": "Other", "appearance": "dark",
         "palette": {"background": "#102030", "success": "#00FF00", "warning": "#FFFF00", "danger": "#FF0000"}}
        """##.write(to: root.appendingPathComponent("other.scheme"), atomically: true, encoding: .utf8)

        let (host, tm) = makeHost(catalog: ThemeCatalog(bundle: .main, userRoots: [root]))
        let before = host.theme.statusColors
        tm.setTheme("other")
        for _ in 0..<20 where host.theme.tokens.themeID != "otherScheme" { await Task.yield() }
        #expect(tm.colorSchemeID(for: .dark) == nil)
        #expect(host.theme.tokens.themeID == "otherScheme")
        #expect(host.theme.tokens.background.hexString == "102030")
        #expect(host.theme.statusColors == HostStatusColors(from: tm.skin))
        #expect(host.theme.statusColors != before)
    }

    @Test("HostThemeTokens(skin:) records the scheme id (= the old theme raw value) as id")
    func fromThemeID() {
        for id in neonSchemeIDs {
            #expect(HostThemeTokens(skin: NeonSchemes.skin(id)).themeID == id)
        }
    }
}
