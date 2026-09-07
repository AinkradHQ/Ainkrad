import Foundation
import Observation
import AinkradHostRuntime

/// View-model for the App Store overlay. Owns all UI state and derives a flat
/// `[AppStoreRow]` from the cached catalog + installed-state + the registry.
@MainActor
@Observable
final class AppStoreStore {
    enum Filter: CaseIterable, Hashable { case all, installed, updates }

    var filter: Filter = .all
    /// Live search over `rows`, composed with `filter` (AIN-148). Client-side
    /// only — filters whatever's already loaded, no network.
    var searchQuery: String = ""
    private(set) var rows: [AppStoreRow] = []
    private(set) var busy: Set<String> = []
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

    init(service: AppStoreServing, registry: BuiltInAppRegistry) {
        self.service = service
        self.registry = registry
    }

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

    /// The row for whichever app's detail page is open (AIN-147), if any.
    var selectedRow: AppStoreRow? {
        guard let selectedAppID else { return nil }
        return rows.first { $0.id == selectedAppID }
    }

    var visibleRows: [AppStoreRow] {
        let filtered: [AppStoreRow]
        switch filter {
        case .all: filtered = rows
        case .installed: filtered = rows.filter { $0.status != .available }
        case .updates: filtered = rows.filter { $0.status == .updateAvailable }
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
            installedRows.append(AppStoreRow(
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
                author: entry?.author))
        }

        var availableRows: [AppStoreRow] = []
        for entry in catalog where !installedIDs.contains(entry.appID) {
            availableRows.append(AppStoreRow(
                id: entry.appID, displayName: entry.displayName, icon: entry.icon,
                description: entry.description, catalogVersion: entry.version,
                installedVersion: nil, status: .available, isEnabled: false,
                kind: entry.kind == .mcpServer ? .mcpServer : .plugin,
                isManaged: false, author: entry.author))
        }

        rows = installedRows.sorted { $0.displayName < $1.displayName }
             + availableRows.sorted { $0.displayName < $1.displayName }
    }

    /// Fetch the catalog (offline → cache) then recompute rows.
    func refresh() async {
        isRefreshing = true
        _ = await service.refreshCatalog()
        isRefreshing = false
        reloadRows()
    }

    func install(_ id: String) async {
        if service.hasRetainedData(appID: id) { pendingReinstall = id; return }
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

    func update(_ id: String) async  {
        await run(id, .update) { try await self.service.update(appID: id) }
    }

    func uninstall(_ id: String) {
        do { try service.uninstall(appID: id) }
        catch let e as AppStoreError { error = e }
        catch { self.error = .notInstalled(id) }
        reloadRows()
    }

    func setEnabled(_ enabled: Bool, for id: String) {
        registry.setEnabled(enabled, for: id)
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

    /// Runs an async action for one app id, tracking busy + surfacing errors,
    /// always clearing busy and recomputing rows afterwards.
    private func run(_ id: String, _ operation: Operation,
                     _ op: @escaping () async throws -> Void) async {
        busy.insert(id)
        var failure: Error?
        do { try await op() }
        catch let e as AppStoreError { error = e; failure = e }
        catch {
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
