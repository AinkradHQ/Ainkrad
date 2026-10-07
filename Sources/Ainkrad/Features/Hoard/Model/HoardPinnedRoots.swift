import AinkradHostRuntime
import Foundation
import Observation

/// Its own document rather than a field on `HoardSettingsDocument`: pins are
/// user data, display settings are preferences, and adding a field to an
/// existing `Codable` document makes every previously-saved copy fail to
/// decode — which would silently reset the user's settings on upgrade.
struct HoardPinnedRootsDocument: PersistableDocument {
    static let documentID = "files-pinned-roots"

    var paths: [String] = []

    init(paths: [String] = []) { self.paths = paths }
}

/// The sidebar's user-pinned favourites.
///
/// Pane-independent and app-wide: a favourite pinned in one pane must appear in
/// every pane, so this lives in `AppEnvironment` beside the other Hoard
/// services rather than inside `HoardPaneStore`.
@MainActor
@Observable
final class HoardPinnedRoots {
    /// Directly stored, persisted in `didSet` — the same rule the icon-size
    /// slider had to learn: `@Observable` only reliably tracks stored state.
    private(set) var roots: [URL] = []

    private let persistence: PersistenceStore

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        let document = persistence.load(HoardPinnedRootsDocument.self)
        roots = (document?.paths ?? []).map { URL(fileURLWithPath: $0) }
    }

    /// Compared through `NavigationHistory.canonical` — `standardizedFileURL`
    /// alone keeps a trailing slash, and `URL` equality is textual, so
    /// "/work/thing/" and "/work/thing" would be two different pins. Same trap
    /// that broke `ascend()` in M1.
    func isPinned(_ url: URL) -> Bool {
        let target = NavigationHistory.canonical(url)
        return roots.contains { NavigationHistory.canonical($0) == target }
    }

    /// Pinning something already pinned is a no-op, not a duplicate row.
    func pin(_ url: URL) {
        guard !isPinned(url) else { return }
        roots.append(NavigationHistory.canonical(url))
        persist()
    }

    func unpin(_ url: URL) {
        let target = NavigationHistory.canonical(url)
        roots.removeAll { NavigationHistory.canonical($0) == target }
        persist()
    }

    func toggle(_ url: URL) {
        isPinned(url) ? unpin(url) : pin(url)
    }

    private func persist() {
        persistence.save(HoardPinnedRootsDocument(paths: roots.map(\.path)))
    }
}
