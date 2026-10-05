import AinkradAppKit
import AinkradHostRuntime
import Observation

/// Backs the ⌘K Launcher overlay: fuzzy-filtered enabled apps and the
/// open-app action. Workspace management deliberately does NOT live here —
/// it has its own surface and shortcut (see ADR-0008's implementation
/// note). The overlay UI is a separate rendering layer on this store.
@MainActor
@Observable
final class LauncherStore {
    var query: String = ""

    /// Set post-construction from `AppEnvironment.bootstrap` (`environment`
    /// doesn't exist yet when `launcherStore` itself is built) — invoked
    /// instead of tiling for `.overlay`-presentation apps (Slice 3), mirroring
    /// how the Settings/App Store sentinel rows flip an `AppEnvironment` flag.
    var presentOverlay: ((String) -> Void)?

    private let registry: BuiltInAppRegistry
    private let workspaceManager: WorkspaceManager
    private let appAppearanceStore: AppAppearanceStore

    init(registry: BuiltInAppRegistry, workspaceManager: WorkspaceManager, appAppearanceStore: AppAppearanceStore) {
        self.registry = registry
        self.workspaceManager = workspaceManager
        self.appAppearanceStore = appAppearanceStore
    }

    var appResults: [RegisteredApp] {
        registry.enabledApps.filter { fuzzyMatches(query: query, target: $0.displayName) }
    }

    /// `.overlay`-presentation apps are summoned as a floating host overlay
    /// instead of tiling (Slice 3). Otherwise: the main workspace is the home
    /// island and stays empty, so summoning an app from it spawns a fresh
    /// workspace (and switches to it); on any other workspace the app splits
    /// into the current layout.
    func selectApp(_ app: RegisteredApp) {
        let effective = appAppearanceStore.presentationOverride(app.id) ?? app.presentation
        guard effective == .pane else {
            presentOverlay?(app.id)
            return
        }
        if workspaceManager.activeWorkspace.isMain {
            workspaceManager.createWorkspace().tileLayout.openApp(app.id)
        } else {
            workspaceManager.activeWorkspace.tileLayout.openApp(app.id)
        }
    }
}
