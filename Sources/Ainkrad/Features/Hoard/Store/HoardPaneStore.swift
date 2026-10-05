import AinkradHostRuntime
import Foundation
import Observation

/// One Hoard pane's state: its tabs, which is active, and the persistence of
/// both. View preferences (hidden files, sort) are pane-wide — they apply to
/// every tab, which is what users expect from a Finder-style toggle.
@MainActor
@Observable
final class HoardPaneStore {
    private let fileSystem: any FileSystemServing
    private let persistence: PersistenceStore

    private(set) var tabs: [HoardTab] = []
    private(set) var activeTabIndex = 0

    var activeTab: HoardTab { tabs[activeTabIndex] }

    init(fileSystem: any FileSystemServing, persistence: PersistenceStore) {
        self.fileSystem = fileSystem
        self.persistence = persistence
        restore()
    }

    func newTab(at directory: URL? = nil) {
        let target = directory ?? activeTab.currentDirectory
        tabs.append(HoardTab(directory: target, fileSystem: fileSystem))
        activeTabIndex = tabs.count - 1
        persist()
    }

    /// Closing the only tab is refused — a pane with zero tabs has nothing to
    /// render and no way back.
    func closeTab(at index: Int) {
        guard tabs.count > 1, tabs.indices.contains(index) else { return }
        tabs.remove(at: index)
        if activeTabIndex >= index {
            activeTabIndex = max(0, activeTabIndex - 1)
        }
        persist()
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeTabIndex = index
        persist()
    }

    func persist() {
        persistence.save(
            HoardPaneDocument(
                tabPaths: tabs.map(\.currentDirectory.path),
                activeTabIndex: activeTabIndex,
                showHidden: activeTab.showHidden,
                showIgnored: activeTab.showIgnored,
                sortKey: activeTab.sortKey.rawValue,
                sortAscending: activeTab.sortAscending
            ))
    }

    private func restore() {
        let home = fileSystem.homeDirectory
        guard let document = persistence.load(HoardPaneDocument.self), !document.tabPaths.isEmpty else {
            tabs = [HoardTab(directory: home, fileSystem: fileSystem)]
            activeTabIndex = 0
            return
        }

        let sortKey = FileSortKey(rawValue: document.sortKey) ?? .name
        tabs = document.tabPaths.map { path in
            let url = URL(fileURLWithPath: path)
            // A directory that vanished between sessions (an ejected volume, a
            // deleted folder) falls back to home rather than restoring a tab
            // that can only show an error.
            let target = fileSystem.isDirectory(url) ? url : home
            let tab = HoardTab(directory: target, fileSystem: fileSystem)
            tab.showHidden = document.showHidden
            tab.showIgnored = document.showIgnored ?? false
            tab.sortKey = sortKey
            tab.sortAscending = document.sortAscending
            return tab
        }
        activeTabIndex = tabs.indices.contains(document.activeTabIndex) ? document.activeTabIndex : 0
    }
}
