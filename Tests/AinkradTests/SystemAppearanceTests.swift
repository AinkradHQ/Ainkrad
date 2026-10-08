import AinkradAppKit
import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad
@testable import AinkradHostRuntime

/// E1.6: the composed appearance follows the system when the theme has both
/// variants, a dark-only theme pins dark, and plugins get the terminal palette.
@Suite("System appearance")
@MainActor
struct SystemAppearanceTests {
    let store = InMemoryPersistenceStore()

    private func manager(_ system: StubSystemAppearance, fixtures: Bool = false) -> ThemeManager {
        let roots = fixtures ? [ThemeFixtures.tempDir(ThemeFixtures.lightVariant)] : []
        return ThemeManager(
            persistence: store, catalog: ThemeCatalog(bundle: .main, userRoots: roots), systemAppearance: system)
    }

    private func host(_ tm: ThemeManager) -> HostServicesImpl {
        HostServicesImpl(
            appID: "t", dataRootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            secretStore: InMemorySecretStore(), themeManager: tm,
            hub: AgentContextRegistryHub(), actionHub: AgentActionRegistryHub(),
            launchHub: PluginLaunchHub(), signalHub: SignalEmitterHub(),
            declaredPresentation: .pane,
            appAppearanceStore: AppAppearanceStore(persistence: InMemoryPersistenceStore()))
    }

    @Test("Neon (dark-only) composes the identical dark skin with the system in light mode", arguments: neonSchemeIDs)
    func neonStaysDark(scheme: String) {
        let system = StubSystemAppearance(.light)
        let tm = manager(system)
        tm.setColorScheme(scheme, for: .dark)
        #expect(tm.appearance == .dark)
        #expect(tm.skin == NeonSchemes.skin(scheme))
        #expect(tm.composedKey == "neon.dark|\(scheme)")
        #expect(LegacyPalettes.hexes(tm.skin) == LegacyPalettes.table[scheme])

        // Flipping the system does nothing under a dark-only theme — no recompose, no callback.
        var changes = 0
        tm.onThemeChange = { changes += 1 }
        system.current = .dark
        system.current = .light
        #expect(changes == 0)
        #expect(tm.skin == NeonSchemes.skin(scheme))
    }

    @Test("a theme with both variants switches skins live; HostServices republishes the terminal palette")
    func bothVariantsFollowSystem() async {
        store.save(GlobalSettings(theme: "glassy"))
        let system = StubSystemAppearance(.dark)
        let tm = manager(system, fixtures: true)
        let services = host(tm)
        #expect(tm.appearance == .dark)
        #expect(tm.skin.id == "nord")
        #expect(services.theme.terminalPalette == HostTerminalPalette(tm.skin.terminal))

        system.current = .light
        #expect(tm.appearance == .light)
        #expect(tm.skin.id == "paper")
        #expect(tm.composedKey == "glassy.light|paper")
        for _ in 0..<20 where services.theme.tokens.themeID != "paper" { await Task.yield() }
        #expect(services.theme.tokens.themeID == "paper")
        #expect(services.theme.terminalPalette == HostTerminalPalette(tm.skin.terminal))

        // A per-appearance scheme choice applies to its own appearance only.
        tm.setColorScheme("dracula", for: .dark)
        #expect(tm.skin.id == "paper")
        system.current = .dark
        #expect(tm.skin.id == "dracula")
        for _ in 0..<20 where services.theme.tokens.themeID != "dracula" { await Task.yield() }
        #expect(services.theme.terminalPalette == HostTerminalPalette(tm.skin.terminal))
    }

    @Test("the terminal palette is published from launch")
    func paletteAtLaunch() {
        let tm = manager(StubSystemAppearance(.light))
        #expect(host(tm).theme.terminalPalette == HostTerminalPalette(NeonSchemes.skin("neonBlue").terminal))
    }

    @Test("-AinkradAppearance wins over the system while set")
    func launchAppearanceWins() {
        let system = StubSystemAppearance(.dark)
        let tm = manager(system, fixtures: true)
        tm.applyLaunchOverride(theme: "glassy", colorScheme: "paper", appearance: .light)
        #expect(tm.appearance == .light)
        #expect(tm.skin.id == "paper")
        system.current = .dark
        #expect(tm.skin.id == "paper")
        // Under Neon the override cannot make a light skin: there is none.
        tm.applyLaunchOverride(theme: "neon", colorScheme: nil, appearance: .light)
        #expect(tm.appearance == .dark)
        #expect(tm.skin.id == "neonBlue")
    }
}
