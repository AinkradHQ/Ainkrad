import AinkradAppKit
import AinkradHostRuntime
import Foundation
import SwiftUI
import Testing

@testable import Ainkrad

@Suite("LauncherStore")
@MainActor
final class LauncherStoreTests {
    private let terminalApp = RegisteredApp(
        id: "terminal", displayName: "Terminal", icon: "terminal",
        isEnabledByDefault: true, source: .builtIn,
        makeRootView: { AnyView(Text("Terminal")) },
        makeSettingsView: { AnyView(Text("Terminal Settings")) },
        chromeFill: { nil }
    )
    private let settingsApp = RegisteredApp(
        id: "settings", displayName: "Settings", icon: "gearshape",
        isEnabledByDefault: true, source: .builtIn,
        makeRootView: { AnyView(Text("Settings")) },
        makeSettingsView: { AnyView(Text("Settings Settings")) },
        chromeFill: { nil }
    )

    private func makeStore() -> (LauncherStore, BuiltInAppRegistry, WorkspaceManager, AppAppearanceStore) {
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore())
        registry.install(builtIn: [terminalApp, settingsApp])
        let workspaceManager = WorkspaceManager()
        let appearance = AppAppearanceStore(persistence: InMemoryPersistenceStore())
        let store = LauncherStore(
            registry: registry, workspaceManager: workspaceManager, appAppearanceStore: appearance)
        return (store, registry, workspaceManager, appearance)
    }

    @Test("with no query, appResults lists every enabled app")
    func appResultsListsEnabledApps() {
        let (store, registry, _, _) = makeStore()
        registry.setEnabled(false, for: "settings")

        #expect(store.appResults.map { $0.id } == ["terminal"])
    }

    @Test("typing fuzzy-filters appResults")
    func appResultsFuzzyFilters() {
        let (store, _, _, _) = makeStore()
        store.query = "trm"
        #expect(store.appResults.map { $0.id } == ["terminal"])
    }

    @Test("selectApp from the main workspace creates a new workspace and opens the app there")
    func selectAppFromMainCreatesNewWorkspace() {
        let (store, _, workspaceManager, _) = makeStore()
        let main = workspaceManager.activeWorkspace
        #expect(main.isMain)

        store.selectApp(terminalApp)

        #expect(workspaceManager.workspaces.count == 2)
        #expect(main.tileLayout.isEmpty)
        #expect(!workspaceManager.activeWorkspace.isMain)
        #expect(workspaceManager.activeWorkspace.tileLayout.appIDs == ["terminal"])
    }

    @Test("selectApp on a non-main workspace splits into the current layout")
    func selectAppOnNonMainSplitsInPlace() {
        let (store, _, workspaceManager, _) = makeStore()
        let mission = workspaceManager.createWorkspace()

        store.selectApp(terminalApp)
        store.selectApp(settingsApp)

        #expect(workspaceManager.workspaces.count == 2)
        #expect(workspaceManager.activeWorkspace.id == mission.id)
        #expect(mission.tileLayout.appIDs == ["terminal", "settings"])
    }

    @Test("an overlay override routes a pane-declared app to the overlay instead of tiling")
    func overrideRoutesToOverlay() {
        let (store, _, workspaceManager, appearance) = makeStore()
        var overlaid: String? = nil
        store.presentOverlay = { overlaid = $0 }

        appearance.setPresentationOverride("terminal", .overlay)  // terminalApp declares .pane by default
        store.selectApp(terminalApp)

        #expect(overlaid == "terminal")
        #expect(workspaceManager.workspaces.count == 1)  // no new workspace created; it went to overlay
    }
}
