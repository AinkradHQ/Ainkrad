import AinkradHostRuntime
import Foundation
import Observation

/// State owner for the App Store overlay. Owns all UI state and derives a flat
/// `[AppStoreRow]` from the cached catalog + installed-state + the registry.
@MainActor
@Observable
final class AppStoreStore {
    enum Filter: CaseIterable, Hashable { case all, installed, updates }
    /// Apps, or themes and colour schemes (E4.4).
    enum Tab: CaseIterable, Hashable { case apps, themes }

    var filter: Filter = .all
    var tab: Tab = .apps
    /// Live search over `rows`, composed with `filter` (AIN-148). Client-side
    /// only — filters whatever's already loaded, no network.
    var searchQuery: String = ""
    private(set) var rows: [AppStoreRow] = []
    /// The Themes tab's rows, kept apart from `rows` so a theme id can never
    /// shadow an app id.
    private(set) var themeRows: [AppStoreRow] = []
    /// The last refused theme install or update, with the installer's problem text.
    var themeFailure: ThemeFailure?

    struct ThemeFailure: Equatable {
        let name: String
        let text: String
    }
    private(set) var busy: Set<String> = []
    /// Apps whose new bundle is on disk while the old one is still mapped.
    private(set) var needsRestart: Set<String> = []
    /// Seam for tests: whether `<appID>.bundle` is already loaded.
    var isBundleLoaded: (String) -> Bool = { AppStoreStore.isBundleLoaded(appID: $0) }
    private(set) var isRefreshing = false
    var error: AppStoreError?
    /// Non-nil while a reinstall of this appID awaits the user's Restore/Reset
    /// choice (retained data exists). Drives the overlay's modal.
    private(set) var pendingReinstall: String? = nil
    /// Non-nil while the detail page for this appID is open (AIN-147). The
    /// overlay swaps its grid for `AppStoreDetailView` while this is set.
    private(set) var selectedAppID: String? = nil
    /// Non-nil while the full-screen screenshot lightbox is open (AIN-147):
    /// the gallery being viewed + the index of the shown image. Opened by
    /// clicking a detail-page screenshot; ⟨/⟩ navigation wraps around.
    private(set) var lightbox: Lightbox? = nil

    struct Lightbox: Equatable {
        var urls: [URL]
        var index: Int
    }

    private let service: AppStoreServing
    private let registry: BuiltInAppRegistry
    /// Applies installed themes and says which are in use; nil in app-only tests.
    private let themeManager: ThemeManager?

    /// What kind of long operation finished, for `onOperationFinished`.
    enum Operation: String, Sendable {
        case install, update
    }
    /// Fired when an install/update finishes, successfully or not. A callback
    /// rather than a `SignalCenter` dependency: this store's job is the app
    /// store, and it should not know that a notification feed exists. Same
    /// idiom as `BuiltInAppRegistry.onAppTornDown`.
    @ObservationIgnored
    var onOperationFinished: ((Operation, String, Error?) -> Void)?

    init(service: AppStoreServing, registry: BuiltInAppRegistry, themeManager: ThemeManager? = nil) {
        self.service = service
        self.registry = registry
        self.themeManager = themeManager
    }

    /// The current tab's rows.
    var currentRows: [AppStoreRow] { tab == .apps ? rows : themeRows }

    /// Plugin bundles that were found on disk but refused to load this launch,
    /// with the reason each was rejected.
    ///
    /// Until now this was recorded by `PluginLoader` into
    /// `BuiltInAppRegistry.loadFailures` and read by *nothing* — so a plugin
    /// that failed to load was indistinguishable from a plugin that was never
    /// installed, and the app just looked like it had no apps. This is the
    /// error channel; the App Store overlay renders it above the grid.
    var loadFailures: [PluginLoadFailure] { registry.loadFailures }

    /// A user-facing one-liner for a rejected bundle: the bundle's name (not
    /// its full path, which is an unhelpful Application Support URL) and the
    /// reason recorded by the loader.
    static func failureText(_ failure: PluginLoadFailure) -> String {
        let name = failure.url.deletingPathExtension().lastPathComponent
        return "\(name) — \(failure.reason)"
    }

    /// The icon and copy the grid shows when no row is visible.
    struct EmptyState: Equatable {
        let icon: String
        let title: String
        let message: String
    }

    /// What an empty grid says: a search that matched nothing, or the
    /// current filter having nothing in it.
    var emptyState: EmptyState {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let things = tab == .apps ? "apps" : "themes"
        if !trimmedQuery.isEmpty {
            return EmptyState(
                icon: "magnifyingglass", title: "No Matches", message: "No \(things) match \"\(trimmedQuery)\".")
        }
        if tab == .themes && filter == .all {
            return EmptyState(
                icon: "paintbrush", title: "No Themes", message: "No themes available — check back later.")
        }
        switch filter {
        case .all:
            return EmptyState(
                icon: "square.grid.2x2", title: "No Apps", message: "No apps available — check back later.")
        case .installed:
            return EmptyState(icon: "shippingbox", title: "Nothing Installed", message: "Nothing installed yet.")
        case .updates:
            return EmptyState(icon: "checkmark.seal", title: "Up to Date", message: "Everything is up to date.")
        }
    }

    /// The row for whichever app's detail page is open (AIN-147), if any.
    var selectedRow: AppStoreRow? {
        guard let selectedAppID else { return nil }
        return currentRows.first { $0.id == selectedAppID }
    }

    var visibleRows: [AppStoreRow] {
        let filtered: [AppStoreRow]
        switch filter {
        case .all: filtered = currentRows
        case .installed: filtered = currentRows.filter { $0.status != .available }
        case .updates: filtered = currentRows.filter { $0.status == .updateAvailable }
        }
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return filtered }
        return filtered.filter { Self.matches($0, query: searchQuery) }
    }

    /// True when `row` matches `query` on `displayName`, `description`, or
    /// `author` (case-insensitive). An empty or whitespace-only query matches
    /// everything. Pure and free of store state so it's directly unit-testable.
    static func matches(_ row: AppStoreRow, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let needle = trimmed.lowercased()
        if row.displayName.lowercased().contains(needle) { return true }
        if row.description.lowercased().contains(needle) { return true }
        if let author = row.author, author.lowercased().contains(needle) { return true }
        return false
    }

    /// Recompute rows from the current cached catalog + installed doc + registry.
    /// No network. Installed rows (built-ins + installed plugins) sort first by
    /// name; available (catalog-only) rows follow, also by name.
    func reloadRows() {
        let catalog = service.cachedCatalog
        let catalogByID = Dictionary(catalog.map { ($0.appID, $0) }, uniquingKeysWith: { a, _ in a })
        let installedDoc = service.installedApps()
        let updates = Set(service.availableUpdates().map(\.appID))
        let registeredByID = Dictionary(registry.allApps.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        var installedIDs = Set(registry.allApps.map(\.id))
        installedIDs.formUnion(installedDoc.keys)

        var installedRows: [AppStoreRow] = []
        for id in installedIDs {
            let reg = registeredByID[id]
            let entry = catalogByID[id]
            let isBuiltIn = reg?.source == .builtIn
            let kind: AppStoreRowKind = entry?.kind == .mcpServer ? .mcpServer : (isBuiltIn ? .builtIn : .plugin)
            installedRows.append(
                AppStoreRow(
                    id: id,
                    displayName: reg?.displayName ?? entry?.displayName ?? id,
                    icon: reg?.icon ?? entry?.icon ?? "app",
                    // Built-ins (no catalog entry) carry their own registered
                    // summary; plugins fall back to the catalog description.
                    description: (reg?.summary).flatMap { $0.isEmpty ? nil : $0 } ?? entry?.description ?? "",
                    catalogVersion: entry?.version,
                    installedVersion: installedDoc[id]?.version,
                    status: updates.contains(id) ? .updateAvailable : .installed,
                    isEnabled: registry.isEnabled(id),
                    kind: kind,
                    isManaged: installedDoc[id] != nil,
                    author: entry?.author,
                    needsRestart: needsRestart.contains(id)))
        }

        var availableRows: [AppStoreRow] = []
        for entry in catalog where !installedIDs.contains(entry.appID) {
            availableRows.append(
                AppStoreRow(
                    id: entry.appID, displayName: entry.displayName, icon: entry.icon,
                    description: entry.description, catalogVersion: entry.version,
                    installedVersion: nil, status: .available, isEnabled: false,
                    kind: entry.kind == .mcpServer ? .mcpServer : .plugin,
                    isManaged: false, author: entry.author))
        }

        rows =
            installedRows.sorted { $0.displayName < $1.displayName }
            + availableRows.sorted { $0.displayName < $1.displayName }
        themeRows = Self.themeRows(
            entries: service.themeCatalog, installed: service.installedThemes(), themeManager: themeManager)
    }

    /// Fetch the catalog (offline → cache) then recompute rows.
    func refresh() async {
        isRefreshing = true
        _ = await service.refreshCatalog()
        isRefreshing = false
        reloadRows()
    }

    func install(_ id: String) async {
        if isThemeRow(id) { return await installTheme(id) }
        if service.hasRetainedData(appID: id) {
            pendingReinstall = id
            return
        }
        await run(id, .install) { try await self.service.install(appID: id) }
    }

    /// Reinstall keeping the retained settings.
    func restoreAndInstall(_ id: String) async {
        service.restoreRetainedData(appID: id)
        pendingReinstall = nil
        await run(id, .install) { try await self.service.install(appID: id) }
    }

    /// Reinstall discarding the retained settings (fresh defaults).
    func resetAndInstall(_ id: String) async {
        service.discardRetainedData(appID: id)
        pendingReinstall = nil
        await run(id, .install) { try await self.service.install(appID: id) }
    }

    /// Dismiss the reinstall prompt without installing.
    func cancelReinstall() { pendingReinstall = nil }

    func update(_ id: String) async {
        if isThemeRow(id) { return await installTheme(id) }
        await run(id, .update) { try await self.service.update(appID: id) }
    }

    func uninstall(_ id: String) {
        if isThemeRow(id) {
            do { try service.uninstallTheme(id: id) } catch {
                themeFailure = ThemeFailure(name: themeName(id), text: Self.themeFailureText(error))
            }
            return reloadRows()
        }
        do { try service.uninstall(appID: id) } catch let e as AppStoreError { error = e } catch {
            self.error = .notInstalled(id)
        }
        reloadRows()
    }

    func setEnabled(_ enabled: Bool, for id: String) {
        registry.setEnabled(enabled, for: id)
        reloadRows()
    }

    // MARK: Themes (E4.4)

    /// Makes an installed theme or colour scheme the one in use, through
    /// `ThemeManager` like Settings does.
    func apply(_ id: String) {
        guard let themeManager, let row = themeRows.first(where: { $0.id == id }) else { return }
        if row.kind == .theme {
            themeManager.setTheme(id)
        } else if let appearance = ThemeAppearance.allCases.first(where: { appearance in
            themeManager.colorSchemes(for: appearance).contains { $0.id == id }
        }) {
            themeManager.setColorScheme(id, for: appearance)
        }
        reloadRows()
    }

    /// The store entry behind a Themes-tab row, for the detail page.
    func themeEntry(for id: String) -> ThemeCatalogEntry? { service.themeCatalog.first { $0.id == id } }

    private func isThemeRow(_ id: String) -> Bool { tab == .themes && themeRows.contains { $0.id == id } }

    private func themeName(_ id: String) -> String { themeRows.first { $0.id == id }?.displayName ?? id }

    /// Install or update (the installer replaces an installed copy). Live at
    /// once through `ThemeManager.reloadCatalog()`, so never `needsRestart`.
    private func installTheme(_ id: String) async {
        guard let entry = themeEntry(for: id) else { return }
        busy.insert(id)
        themeFailure = nil
        do { try await service.installTheme(entry) } catch {
            themeFailure = ThemeFailure(name: entry.displayName, text: Self.themeFailureText(error))
        }
        busy.remove(id)
        reloadRows()
    }

    /// Opens the detail page for `appID` (AIN-147).
    func openDetail(_ appID: String) { selectedAppID = appID }

    /// Closes the detail page, returning the overlay to the grid.
    func closeDetail() { selectedAppID = nil }

    // MARK: Screenshot lightbox (AIN-147)

    /// Opens the lightbox on `urls[index]`. No-op for an empty gallery or an
    /// out-of-range index, so a stale tap can never open a broken viewer.
    func openLightbox(_ urls: [URL], at index: Int) {
        guard urls.indices.contains(index) else { return }
        lightbox = Lightbox(urls: urls, index: index)
    }

    func closeLightbox() { lightbox = nil }

    /// Advance to the next screenshot, wrapping from the last back to the first.
    func lightboxNext() { stepLightbox(1) }

    /// Step back to the previous screenshot, wrapping from the first to the last.
    func lightboxPrevious() { stepLightbox(-1) }

    private func stepLightbox(_ delta: Int) {
        guard var box = lightbox, !box.urls.isEmpty else { return }
        let count = box.urls.count
        box.index = ((box.index + delta) % count + count) % count
        lightbox = box
    }

    /// The full catalog record for `appID`, if it's in the cached catalog —
    /// used by the detail page for the long description/screenshots/links
    /// that don't fit in the flat `AppStoreRow` projection.
    func entry(for appID: String) -> CatalogEntry? {
        service.cachedCatalog.first { $0.appID == appID }
    }

    /// True when this process has already loaded `<appID>.bundle` — the store
    /// installs every plugin at exactly that file name.
    nonisolated static func isBundleLoaded(appID: String) -> Bool {
        Bundle.allBundles.contains { $0.isLoaded && $0.bundleURL.lastPathComponent == "\(appID).bundle" }
    }

    /// Runs an async action for one app id, tracking busy + surfacing errors,
    /// always clearing busy and recomputing rows afterwards.
    private func run(
        _ id: String, _ operation: Operation,
        _ op: @escaping () async throws -> Void
    ) async {
        busy.insert(id)
        // Read BEFORE the swap: the loaded `Bundle` keeps its URL after the
        // new bundle is moved over it, so this still answers afterwards too —
        // but "was it loaded when we started" is the question.
        let wasLoaded = isBundleLoaded(id)
        var failure: Error?
        do {
            try await op()
            if wasLoaded { needsRestart.insert(id) }
        } catch let e as AppStoreError {
            error = e
            failure = e
        } catch {
            self.error = .download(String(describing: error))
            failure = error
        }
        busy.remove(id)
        reloadRows()
        // After `reloadRows()`, so an observer that reads this store sees
        // settled state rather than mid-operation state.
        onOperationFinished?(operation, id, failure)
    }
}
