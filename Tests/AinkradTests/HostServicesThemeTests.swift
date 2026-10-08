import AinkradAppKit
import AinkradHostRuntime
import Foundation
import SwiftUI
import Testing

@testable import Ainkrad

@Suite("HostServices theme")
@MainActor
struct HostServicesThemeTests {
    private func makeHost() -> (HostServicesImpl, ThemeManager) {
        let persistence = InMemoryPersistenceStore()
        let tm = ThemeManager(persistence: persistence)
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

    @Test("HostThemeTokens(skin:) records the scheme id (= the old theme raw value) as id")
    func fromThemeID() {
        for id in neonSchemeIDs {
            #expect(HostThemeTokens(skin: NeonSchemes.skin(id)).themeID == id)
        }
    }
}
