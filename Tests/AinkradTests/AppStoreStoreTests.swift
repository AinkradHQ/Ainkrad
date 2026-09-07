import Testing
import Foundation
import SwiftUI
@testable import Ainkrad
import AinkradHostRuntime

@MainActor
final class FakeAppStoreService: AppStoreServing {
    var cachedCatalog: [CatalogEntry] = []
    var installedResult: [String: InstalledPluginsDocument.Entry] = [:]
    var updatesResult: [CatalogEntry] = []
    var installError: AppStoreError?
    private(set) var installedCalls: [String] = []
    private(set) var uninstalledCalls: [String] = []
    var retained: Set<String> = []
    private(set) var restoredCalls: [String] = []
    private(set) var discardedCalls: [String] = []

    func refreshCatalog() async -> [CatalogEntry] { cachedCatalog }
    func install(appID: String) async throws {
        if let installError { throw installError }
        installedCalls.append(appID)
        let v = cachedCatalog.first { $0.appID == appID }?.version ?? "1.0.0"
        installedResult[appID] = .init(version: v, sourceRepo: "o/\(appID)")
    }
    func update(appID: String) async throws { try await install(appID: appID) }
    func uninstall(appID: String) throws { uninstalledCalls.append(appID); installedResult[appID] = nil }
    func installedApps() -> [String: InstalledPluginsDocument.Entry] { installedResult }
    func availableUpdates() -> [CatalogEntry] { updatesResult }
    func hasRetainedData(appID: String) -> Bool { retained.contains(appID) }
    func restoreRetainedData(appID: String) { restoredCalls.append(appID); retained.remove(appID) }
    func discardRetainedData(appID: String) { discardedCalls.append(appID); retained.remove(appID) }
}

@MainActor
struct AppStoreStoreTests {
    private func entry(_ id: String, _ v: String = "1.0.0") -> CatalogEntry {
        CatalogEntry(appID: id, displayName: id.capitalized, icon: "app", description: "desc \(id)",
                     version: v, apiVersion: 1, downloadURL: URL(string: "https://e/\(id).zip")!,
                     sha256: "x", sourceRepo: "o/\(id)")
    }
    private func builtIn(_ id: String) -> RegisteredApp {
        RegisteredApp(id: id, displayName: id.capitalized, icon: "terminal", isEnabledByDefault: true,
            source: .builtIn, makeRootView: { AnyView(EmptyView()) },
            makeSettingsView: { AnyView(EmptyView()) }, chromeFill: { nil })
    }
    private func plugin(_ id: String) -> RegisteredApp {
        RegisteredApp(id: id, displayName: id.capitalized, icon: "app", isEnabledByDefault: true,
            source: .plugin(url: URL(fileURLWithPath: "/tmp/\(id).bundle"), apiVersion: 1),
            makeRootView: { AnyView(EmptyView()) },
            makeSettingsView: { AnyView(EmptyView()) }, chromeFill: { nil })
    }
    private func store(service: FakeAppStoreService, builtIns: [RegisteredApp] = [],
                      loaded: [RegisteredApp] = []) -> AppStoreStore {
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore())
        registry.install(builtIn: builtIns, loaded: loaded)
        let s = AppStoreStore(service: service, registry: registry)
        s.reloadRows()
        return s
    }

    @Test("a catalog-only app is .available")
    func availableRow() {
        let svc = FakeAppStoreService(); svc.cachedCatalog = [entry("notes")]
        let row = store(service: svc).rows.first { $0.id == "notes" }
        #expect(row?.status == .available)
        #expect(row?.kind == .plugin)
    }

    @Test("a built-in is .installed and .builtIn with no catalog version")
    func builtInRow() {
        let svc = FakeAppStoreService()
        let row = store(service: svc, builtIns: [builtIn("terminal")]).rows.first { $0.id == "terminal" }
        #expect(row?.status == .installed)
        #expect(row?.kind == .builtIn)
    }

    @Test("an installed plugin with a newer catalog version is .updateAvailable")
    func updateRow() {
        let svc = FakeAppStoreService()
        svc.cachedCatalog = [entry("notes", "2.0.0")]
        svc.installedResult = ["notes": .init(version: "1.0.0", sourceRepo: "o/notes")]
        svc.updatesResult = [entry("notes", "2.0.0")]
        let row = store(service: svc).rows.first { $0.id == "notes" }
        #expect(row?.status == .updateAvailable)
        #expect(row?.installedVersion == "1.0.0")
        #expect(row?.catalogVersion == "2.0.0")
    }

    @Test("filters select the right rows")
    func filters() {
        let svc = FakeAppStoreService()
        svc.cachedCatalog = [entry("notes"), entry("timer", "2.0.0")]
        svc.installedResult = ["timer": .init(version: "1.0.0", sourceRepo: "o/timer")]
        svc.updatesResult = [entry("timer", "2.0.0")]
        let s = store(service: svc, builtIns: [builtIn("terminal")])
        s.filter = .all;       #expect(Set(s.visibleRows.map(\.id)) == ["notes", "timer", "terminal"])
        s.filter = .installed;  #expect(Set(s.visibleRows.map(\.id)) == ["timer", "terminal"])
        s.filter = .updates;    #expect(s.visibleRows.map(\.id) == ["timer"])
    }

    @Test("empty catalog still lists the built-in under installed")
    func emptyCatalog() {
        let s = store(service: FakeAppStoreService(), builtIns: [builtIn("terminal")])
        s.filter = .all;       #expect(s.visibleRows.map(\.id) == ["terminal"])
        s.filter = .updates;   #expect(s.visibleRows.isEmpty)
    }

    @Test("install marks busy then clears, and the row becomes installed")
    func installFlow() async {
        let svc = FakeAppStoreService(); svc.cachedCatalog = [entry("notes")]
        let s = store(service: svc)
        #expect(s.rows.first { $0.id == "notes" }?.status == .available)
        await s.install("notes")
        #expect(svc.installedCalls == ["notes"])
        #expect(s.busy.isEmpty)
        #expect(s.rows.first { $0.id == "notes" }?.status == .installed)
        #expect(s.error == nil)
    }

    @Test("a failing install surfaces the error and leaves rows unchanged")
    func installError() async {
        let svc = FakeAppStoreService(); svc.cachedCatalog = [entry("notes")]
        svc.installError = .checksumMismatch
        let s = store(service: svc)
        await s.install("notes")
        #expect(s.error == .checksumMismatch)
        #expect(s.busy.isEmpty)
        #expect(s.rows.first { $0.id == "notes" }?.status == .available)
    }

    @Test("uninstall removes the row")
    func uninstallFlow() {
        let svc = FakeAppStoreService()
        svc.cachedCatalog = [entry("notes")]
        svc.installedResult = ["notes": .init(version: "1.0.0", sourceRepo: "o/notes")]
        let s = store(service: svc)
        #expect(s.rows.first { $0.id == "notes" }?.status == .installed)
        s.uninstall("notes")
        #expect(svc.uninstalledCalls == ["notes"])
        #expect(s.rows.first { $0.id == "notes" }?.status == .available)   // back to catalog-only
    }

    @Test("an App Store-installed plugin is managed (uninstallable)")
    func managedPluginRow() {
        let svc = FakeAppStoreService()
        svc.cachedCatalog = [entry("notes")]
        svc.installedResult = ["notes": .init(version: "1.0.0", sourceRepo: "o/notes")]
        let row = store(service: svc, loaded: [plugin("notes")]).rows.first { $0.id == "notes" }
        #expect(row?.status == .installed)
        #expect(row?.kind == .plugin)
        #expect(row?.isManaged == true)
    }

    @Test("a dev-sideloaded plugin (registered, no installed-doc entry) is NOT managed")
    func devSideloadedPluginRow() {
        // Registered as a plugin, but never App Store-installed → not in the
        // installed doc. Must be visible + installed, but not uninstallable.
        let svc = FakeAppStoreService()   // installedApps() == empty
        let row = store(service: svc, loaded: [plugin("hello")]).rows.first { $0.id == "hello" }
        #expect(row?.status == .installed)
        #expect(row?.kind == .plugin)
        #expect(row?.isManaged == false)
    }

    @Test("a built-in is never managed (not uninstallable via App Store)")
    func builtInNotManaged() {
        let row = store(service: FakeAppStoreService(), builtIns: [builtIn("terminal")]).rows.first { $0.id == "terminal" }
        #expect(row?.isManaged == false)
    }

    @Test("a catalog-only app is not managed")
    func availableNotManaged() {
        let svc = FakeAppStoreService(); svc.cachedCatalog = [entry("notes")]
        #expect(store(service: svc).rows.first { $0.id == "notes" }?.isManaged == false)
    }

    @Test("setEnabled flips the registry-backed enabled flag")
    func enableFlow() {
        let svc = FakeAppStoreService()
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore())
        registry.install(builtIn: [builtIn("terminal")])
        let s = AppStoreStore(service: svc, registry: registry)
        s.reloadRows()
        #expect(s.rows.first { $0.id == "terminal" }?.isEnabled == true)
        s.setEnabled(false, for: "terminal")
        #expect(s.rows.first { $0.id == "terminal" }?.isEnabled == false)
    }

    @Test("install with retained data prompts instead of installing")
    func installPrompts() async {
        let svc = FakeAppStoreService(); svc.cachedCatalog = [entry("notes")]; svc.retained = ["notes"]
        let s = store(service: svc)
        await s.install("notes")
        #expect(s.pendingReinstall == "notes")
        #expect(svc.installedCalls.isEmpty)                    // did NOT install yet
    }

    @Test("install without retained data installs directly (no prompt)")
    func installNoPrompt() async {
        let svc = FakeAppStoreService(); svc.cachedCatalog = [entry("notes")]
        let s = store(service: svc)
        await s.install("notes")
        #expect(s.pendingReinstall == nil)
        #expect(svc.installedCalls == ["notes"])
    }

    @Test("restoreAndInstall restores then installs and clears the prompt")
    func restorePath() async {
        let svc = FakeAppStoreService(); svc.cachedCatalog = [entry("notes")]; svc.retained = ["notes"]
        let s = store(service: svc)
        await s.install("notes")                              // sets pendingReinstall
        await s.restoreAndInstall("notes")
        #expect(svc.restoredCalls == ["notes"])
        #expect(svc.installedCalls == ["notes"])
        #expect(s.pendingReinstall == nil)
    }

    @Test("resetAndInstall discards then installs and clears the prompt")
    func resetPath() async {
        let svc = FakeAppStoreService(); svc.cachedCatalog = [entry("notes")]; svc.retained = ["notes"]
        let s = store(service: svc)
        await s.install("notes")
        await s.resetAndInstall("notes")
        #expect(svc.discardedCalls == ["notes"])
        #expect(svc.installedCalls == ["notes"])
        #expect(s.pendingReinstall == nil)
    }

    @Test("cancelReinstall clears the prompt without installing")
    func cancelPath() async {
        let svc = FakeAppStoreService(); svc.cachedCatalog = [entry("notes")]; svc.retained = ["notes"]
        let s = store(service: svc)
        await s.install("notes")
        s.cancelReinstall()
        #expect(s.pendingReinstall == nil)
        #expect(svc.installedCalls.isEmpty)
    }
}

@MainActor
struct AppStoreLightboxTests {
    private func makeStore() -> AppStoreStore {
        AppStoreStore(service: FakeAppStoreService(),
                      registry: BuiltInAppRegistry(persistence: InMemoryPersistenceStore()))
    }

    private var urls: [URL] {
        [URL(string: "https://e/1.png")!, URL(string: "https://e/2.png")!, URL(string: "https://e/3.png")!]
    }

    @Test("openLightbox shows the tapped image; out-of-range or empty is a no-op")
    func openValidation() {
        let store = makeStore()

        store.openLightbox(urls, at: 1)
        #expect(store.lightbox == .init(urls: urls, index: 1))

        store.closeLightbox()
        #expect(store.lightbox == nil)

        store.openLightbox(urls, at: 3)   // out of range
        #expect(store.lightbox == nil)
        store.openLightbox([], at: 0)     // empty gallery
        #expect(store.lightbox == nil)
    }

    @Test("next/previous wrap around the gallery in both directions")
    func navigationWraps() {
        let store = makeStore()
        store.openLightbox(urls, at: 2)

        store.lightboxNext()
        #expect(store.lightbox?.index == 0)   // last → first

        store.lightboxPrevious()
        #expect(store.lightbox?.index == 2)   // first → last

        store.lightboxPrevious()
        #expect(store.lightbox?.index == 1)
    }

    @Test("navigation with no open lightbox is a no-op")
    func navigationRequiresOpenBox() {
        let store = makeStore()
        store.lightboxNext()
        store.lightboxPrevious()
        #expect(store.lightbox == nil)
    }
}

/// The `onOperationFinished` hook the Signal feed listens on. Separate suite so
/// the existing store tests keep their own shape.
@MainActor
struct AppStoreStoreOperationHookTests {
    private func entry(_ id: String) -> CatalogEntry {
        CatalogEntry(appID: id, displayName: id.capitalized, icon: "app", description: "desc",
                     version: "1.0.0", apiVersion: 1,
                     downloadURL: URL(string: "https://e/\(id).zip")!,
                     sha256: "x", sourceRepo: "o/\(id)")
    }

    private func makeStore(_ service: FakeAppStoreService) -> AppStoreStore {
        AppStoreStore(service: service, registry: BuiltInAppRegistry(persistence: InMemoryPersistenceStore()))
    }

    @Test("a successful install reports the operation with no error")
    func installSuccess() async {
        let service = FakeAppStoreService()
        service.cachedCatalog = [entry("raven")]
        let store = makeStore(service)
        var seen: [(AppStoreStore.Operation, String, Bool)] = []
        store.onOperationFinished = { op, id, error in seen.append((op, id, error != nil)) }

        await store.install("raven")
        #expect(seen.count == 1)
        #expect(seen[0].0 == .install)
        #expect(seen[0].1 == "raven")
        #expect(seen[0].2 == false)
    }

    @Test("a failed install reports the error rather than staying silent")
    func installFailure() async {
        let service = FakeAppStoreService()
        service.cachedCatalog = [entry("raven")]
        service.installError = .notInstalled("raven")
        let store = makeStore(service)
        var seen: [(AppStoreStore.Operation, String, Bool)] = []
        store.onOperationFinished = { op, id, error in seen.append((op, id, error != nil)) }

        await store.install("raven")
        #expect(seen.count == 1)
        #expect(seen[0].2 == true, "a silent failed install is the case this hook exists for")
    }

    @Test("an update is reported as an update, not as an install")
    func updateIsDistinct() async {
        let service = FakeAppStoreService()
        service.cachedCatalog = [entry("quest")]
        let store = makeStore(service)
        var operations: [AppStoreStore.Operation] = []
        store.onOperationFinished = { op, _, _ in operations.append(op) }

        await store.update("quest")
        #expect(operations == [.update],
                "install and update have separate kinds so one can be muted alone")
    }

    @Test("a reinstall prompt does not report an operation until it actually runs")
    func pendingReinstallIsNotAnOutcome() async {
        let service = FakeAppStoreService()
        service.cachedCatalog = [entry("raven")]
        service.retained = ["raven"]
        let store = makeStore(service)
        var count = 0
        store.onOperationFinished = { _, _, _ in count += 1 }

        await store.install("raven")      // becomes a pending-reinstall prompt
        #expect(count == 0, "nothing happened yet, so the feed must stay quiet")
        #expect(store.pendingReinstall == "raven")

        await store.restoreAndInstall("raven")
        #expect(count == 1)
    }
}
