import AinkradAppKit
import AinkradHostRuntime
import Foundation
import SwiftUI
import Testing

@testable import Ainkrad

/// Slice 3: `.overlay`-presentation apps are summoned as a floating host
/// overlay instead of tiling into the workspace layout; `.pane` apps (the
/// default, and all pre-Slice-3 behavior) are unaffected.
@Suite("PluginOverlayLaunch")
@MainActor
final class PluginOverlayLaunchTests {
    private let overlayApp = RegisteredApp(
        id: "quickTool", displayName: "Quick Tool", icon: "bolt",
        isEnabledByDefault: true, source: .builtIn,
        makeRootView: { AnyView(Text("Quick Tool")) },
        makeSettingsView: { AnyView(Text("Quick Tool Settings")) },
        chromeFill: { nil },
        presentation: .overlay
    )
    private let paneApp = RegisteredApp(
        id: "terminal", displayName: "Terminal", icon: "terminal",
        isEnabledByDefault: true, source: .builtIn,
        makeRootView: { AnyView(Text("Terminal")) },
        makeSettingsView: { AnyView(Text("Terminal Settings")) },
        chromeFill: { nil }
        // presentation defaults to .pane
    )

    private func makeStore() -> (LauncherStore, WorkspaceManager) {
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore())
        registry.install(builtIn: [overlayApp, paneApp])
        let workspaceManager = WorkspaceManager()
        let appAppearanceStore = AppAppearanceStore(persistence: InMemoryPersistenceStore())
        let store = LauncherStore(
            registry: registry, workspaceManager: workspaceManager, appAppearanceStore: appAppearanceStore)
        return (store, workspaceManager)
    }

    @Test("selectApp on an .overlay app calls presentOverlay and does not tile")
    func selectAppOverlayPresentsInsteadOfTiling() {
        let (store, workspaceManager) = makeStore()
        let main = workspaceManager.activeWorkspace
        var presentedID: String?
        store.presentOverlay = { presentedID = $0 }

        store.selectApp(overlayApp)

        #expect(presentedID == "quickTool")
        #expect(workspaceManager.workspaces.count == 1)
        #expect(main.tileLayout.isEmpty)
    }

    @Test("selectApp on a .pane app still tiles as before, unaffected by presentOverlay")
    func selectAppPaneStillTiles() {
        let (store, workspaceManager) = makeStore()
        let main = workspaceManager.activeWorkspace
        var presentedID: String?
        store.presentOverlay = { presentedID = $0 }

        store.selectApp(paneApp)

        #expect(presentedID == nil)
        #expect(workspaceManager.workspaces.count == 2)
        #expect(main.tileLayout.isEmpty)
        #expect(!workspaceManager.activeWorkspace.isMain)
        #expect(workspaceManager.activeWorkspace.tileLayout.appIDs == ["terminal"])
    }
}
