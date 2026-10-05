import AinkradHostRuntime
import Foundation

/// What survives a relaunch: which directories were open in which tabs, which
/// was active, and the view preferences. Paths are stored as strings rather
/// than `URL`s so the document stays legible on disk and version-tolerant.
struct HoardPaneDocument: PersistableDocument {
    static let documentID = "files-pane"

    var tabPaths: [String]
    var activeTabIndex: Int
    var showHidden: Bool
    /// Optional so a document written before ⌘⇧. existed still decodes — a
    /// required new key would make every saved pane fail to load and silently
    /// reset the user's tabs.
    var showIgnored: Bool?
    var sortKey: String
    var sortAscending: Bool
}
