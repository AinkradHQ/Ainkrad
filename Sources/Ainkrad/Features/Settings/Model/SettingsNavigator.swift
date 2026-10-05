import AinkradAppKitContract
import Observation

/// Owns which settings page is showing and which field, if any, a deep-link
/// asked us to reveal. Deep-links come from search, ⌘, on a focused app,
/// error toasts, and the assistant.
@MainActor
@Observable
final class SettingsNavigator {
    var selection: SettingsPath
    private(set) var highlightedPath: SettingsPath?

    init(initial: SettingsPath) {
        self.selection = initial
    }

    /// Accepts a page, group, or field path. Unknown paths are ignored
    /// rather than clearing the pane — a stale deep-link should be inert,
    /// not destructive.
    func navigate(to path: SettingsPath, in catalog: SettingsCatalog) {
        let path = SettingsPathAliases.resolve(path)
        guard let page = catalog.page(containing: path) else { return }
        selection = page.path
        highlightedPath = (page.path == path) ? nil : path
    }

    func clearHighlight() {
        highlightedPath = nil
    }
}
