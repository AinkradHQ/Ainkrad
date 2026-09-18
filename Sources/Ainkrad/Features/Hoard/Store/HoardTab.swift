import Foundation
import Observation

/// One tab: a current directory, its listing, the selection within it, and the
/// back/forward history that got there. Owns no views and no `FileManager` —
/// it talks to `FileSystemServing`, so it is fully testable with a fake.
@MainActor
@Observable
final class HoardTab: Identifiable {
    let id = UUID()

    private let fileSystem: any FileSystemServing
    private var history: NavigationHistory

    /// The raw listing, unfiltered and unsorted.
    private(set) var entries: [FileEntry] = []
    /// Human-readable reason the last load failed, or `nil`.
    private(set) var loadError: String?

    /// The display-ordered listing — STORED, not computed.
    ///
    /// This was originally a computed property, which was a real performance
    /// bug: it ran a full filter + sort on every access, and it is read from a
    /// dozen places including twice inside `cursorEntry` and once per render
    /// pass of three views. A single arrow keypress cost several O(n log n)
    /// sorts over the whole directory, which is exactly what made keyboard
    /// navigation feel glitchy in a large folder. Now it is recomputed only
    /// when one of its four inputs actually changes.
    private(set) var visibleEntries: [FileEntry] = []

    var selection: Set<URL> = []

    var sortKey: FileSortKey = .name {
        didSet { if oldValue != sortKey { recomputeVisible() } }
    }
    var sortAscending = true {
        didSet { if oldValue != sortAscending { recomputeVisible() } }
    }
    var showHidden = false {
        didSet { if oldValue != showHidden { recomputeVisible() } }
    }

    /// Separate from `showHidden`, because the two questions are different:
    /// "show me dotfiles" is about the filesystem, "show me build output git
    /// is ignoring" is about the project. In a repo with a large `node_modules`
    /// they are emphatically not the same toggle.
    var showIgnored = false {
        didSet { if oldValue != showIgnored { recomputeVisible() } }
    }

    /// Paths git reports as ignored, relative-resolved to absolute URLs.
    var ignoredURLs: Set<URL> = [] {
        didSet { if oldValue != ignoredURLs { recomputeVisible() } }
    }

    var currentDirectory: URL { history.current }
    var title: String { currentDirectory.lastPathComponent }
    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }

    /// The keyboard cursor's row in `visibleEntries`. Distinct from
    /// `selection`: you move the cursor to look, and select to act — the
    /// orthodox-manager separation that makes Space-to-select meaningful.
    ///
    /// Arrow keys move ONLY this. They deliberately no longer rewrite
    /// `selection` on every press: mutating a `Set<URL>` per keystroke
    /// invalidated every row's `selection.contains` check and re-rendered the
    /// whole list, which is the other half of the glitchiness.
    private(set) var cursorIndex = 0

    var cursorEntry: FileEntry? {
        visibleEntries.indices.contains(cursorIndex) ? visibleEntries[cursorIndex] : nil
    }

    init(directory: URL, fileSystem: any FileSystemServing) {
        self.fileSystem = fileSystem
        self.history = NavigationHistory(root: directory)
        reload()
    }

    private func recomputeVisible() {
        let visible = entries.filter { entry in
            if entry.isHidden && !showHidden { return false }
            if ignoredURLs.contains(entry.url) && !showIgnored { return false }
            return true
        }
        visibleEntries = sortedEntries(visible, by: sortKey, ascending: sortAscending)
        // A stale cursor pointing past the end of a smaller listing would make
        // arrow keys appear dead until the user scrolled back into range.
        cursorIndex = min(cursorIndex, max(0, visibleEntries.count - 1))
    }

    /// Re-reads the current directory. Called on creation, on navigation, and
    /// by the FSEvents watcher.
    func reload() {
        do {
            entries = try fileSystem.contents(of: currentDirectory)
            loadError = nil
        } catch {
            // Degrade, don't crash: empty the list and say why. The pane
            // renders an error state rather than a blank surface.
            entries = []
            loadError = error.localizedDescription
        }
        recomputeVisible()
    }

    /// Navigates to `url` even if it turns out to be unreadable — the failure
    /// then shows up in place, at the path the user asked for, instead of
    /// silently doing nothing and looking broken.
    func navigate(to url: URL) {
        history.visit(url)
        resetCursorAndSelection()
        reload()
    }

    func descend(into entry: FileEntry) {
        guard entry.isDirectory else { return }
        navigate(to: entry.url)
    }

    func ascend() {
        let parent = currentDirectory.deletingLastPathComponent()
        guard parent != currentDirectory else { return }
        navigate(to: parent)
    }

    func goBack() {
        guard history.canGoBack else { return }
        history.goBack()
        resetCursorAndSelection()
        reload()
    }

    func goForward() {
        guard history.canGoForward else { return }
        history.goForward()
        resetCursorAndSelection()
        reload()
    }

    private func resetCursorAndSelection() {
        selection.removeAll()
        cursorIndex = 0
    }

    // MARK: - Cursor

    func moveCursor(by delta: Int) {
        let count = visibleEntries.count
        guard count > 0 else { cursorIndex = 0; return }
        cursorIndex = min(max(0, cursorIndex + delta), count - 1)
    }

    func moveCursorToStart() { cursorIndex = 0 }

    func moveCursorToEnd() {
        cursorIndex = max(0, visibleEntries.count - 1)
    }

    /// Clicking a row puts the cursor there too, so the keyboard picks up from
    /// where the mouse left off instead of jumping back to a stale position.
    func placeCursor(at entry: FileEntry) {
        guard let index = visibleEntries.firstIndex(of: entry) else { return }
        cursorIndex = index
        selection = [entry.url]
    }

    // MARK: - Selection

    /// `extending` is the ⇧-arrow case: add to the selection rather than
    /// replacing it.
    func selectCursor(extending: Bool) {
        guard let entry = cursorEntry else { return }
        if extending {
            selection.insert(entry.url)
        } else {
            selection = [entry.url]
        }
    }

    /// Space: toggle the cursor row's membership, so a second press
    /// deselects. Toggling is what makes Space usable for building a
    /// multi-selection by hand.
    func toggleCursorSelection() {
        guard let entry = cursorEntry else { return }
        if selection.contains(entry.url) {
            selection.remove(entry.url)
        } else {
            selection.insert(entry.url)
        }
    }

    /// Selects the visible entry matching `url`, comparing SYMLINK-RESOLVED
    /// paths.
    ///
    /// Listing URLs come from `FileManager.contentsOfDirectory`, which returns
    /// resolved paths — `/private/var/…` where the caller wrote `/var/…`. A URL
    /// built anywhere else therefore never compares equal to a row, so
    /// selection set from outside the listing (the assistant's `hoard_reveal`,
    /// notably) silently selected nothing.
    @discardableResult
    func select(matching url: URL) -> Bool {
        let wanted = url.resolvingSymlinksInPath().path
        guard let match = visibleEntries.first(where: {
            $0.url.resolvingSymlinksInPath().path == wanted
        }) else { return false }
        placeCursor(at: match)
        return true
    }

    /// Retargets onto `entry` for a context menu, unless it is already part of
    /// the selection.
    ///
    /// The rule everywhere: right-clicking one of three selected files acts on
    /// all three; right-clicking a fourth acts on that one alone. Getting this
    /// backwards means a menu that appears over one file and deletes others.
    func targetContextMenu(at entry: FileEntry) {
        guard !selection.contains(entry.url) else { return }
        // `placeCursor` already replaces the selection wholesale, so the row
        // ends up both cursored and solely selected — which is what the menu's
        // actions then operate on.
        placeCursor(at: entry)
    }

    /// Set by the pane when the host can route a document somewhere. Nil means
    /// "nothing to open into", which is the pre-generation-11 behaviour.
    var onOpenDocument: ((URL) -> Void)?

    func selectAll() {
        selection = Set(visibleEntries.map(\.url))
    }

    func invertSelection() {
        let all = Set(visibleEntries.map(\.url))
        selection = all.subtracting(selection)
    }

    /// Activate an entry: descend into a directory, or hand a markdown file to
    /// Lore.
    ///
    /// ONE activation path, deliberately. Enter and double-click used to be
    /// different code: Enter went through `activateCursor`, while double-click
    /// called `descend(into:)` directly — which guards on `isDirectory` and
    /// silently returns for a file. So teaching Enter to open markdown left
    /// double-click, the thing anyone actually reaches for in a file manager,
    /// doing nothing at all.
    func activate(_ entry: FileEntry) {
        if entry.isDirectory {
            descend(into: entry)
            return
        }
        guard Self.isMarkdown(entry.url) else { return }
        onOpenDocument?(entry.url)
    }

    /// Enter: activate whatever the cursor is on.
    ///
    /// Files did nothing until generation 11. They still do nothing here for
    /// anything that is not markdown: this is deliberately NOT a general
    /// file-opener. Widening it to "open whatever with whatever" is a different
    /// feature with a different set of ways to go wrong, and Enter on a binary
    /// doing something surprising is worse than Enter doing nothing.
    ///
    /// `onOpenDocument` is nil wherever nothing is wired (tests, a pane built
    /// without the host), so the old do-nothing behaviour is still the floor.
    func activateCursor() {
        guard let entry = cursorEntry else { return }
        activate(entry)
    }

    /// Markdown by extension. Lore's own engine registry is the authority on
    /// what it can render, but it lives in the plugin and this is the host —
    /// so this is the narrow, boring subset rather than a guess at that.
    static func isMarkdown(_ url: URL) -> Bool {
        ["md", "markdown", "mdown", "mkd"].contains(url.pathExtension.lowercased())
    }
}
