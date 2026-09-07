import Testing
import Foundation
import SwiftUI
@testable import Ainkrad
import AinkradAppKit
import AinkradHostRuntime

@Suite("HostServices theme")
@MainActor
struct HostServicesThemeTests {
    private func makeHost() -> (HostServicesImpl, ThemeManager) {
        let persistence = InMemoryPersistenceStore()
        let tm = ThemeManager(persistence: persistence)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let host = HostServicesImpl(appID: "t", dataRootURL: root,
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

        tm.setTheme(.dracula)
        for _ in 0..<20 where host.theme.tokens.themeID != "dracula" { await Task.yield() }
        #expect(host.theme.tokens.themeID == "dracula")
        #expect(host.theme.tokens.background == Color(hex: "1A1B23"))

        // A second change must also propagate — guards the self-re-arm.
        tm.setTheme(.nord)
        for _ in 0..<20 where host.theme.tokens.themeID != "nord" { await Task.yield() }
        #expect(host.theme.tokens.themeID == "nord")
    }

    @Test("HostThemeTokens(from:) records the theme rawValue as id")
    func fromThemeID() {
        #expect(HostThemeTokens(from: .neonBlue).themeID == "neonBlue")
        #expect(HostThemeTokens(from: .cyberPurple).themeID == "cyberPurple")
    }
}
