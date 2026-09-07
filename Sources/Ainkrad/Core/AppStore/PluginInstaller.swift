import Foundation
import CryptoKit
import AinkradAppKit
import AinkradHostRuntime

enum AppStoreError: Error, Equatable {
    case download(String)
    case checksumMismatch
    case unpack(String)
    case invalidBundle(String)
    case notInstalled(String)
    case notNewer
}

/// Installs / updates / uninstalls plugin bundles from catalog entries. All
/// filesystem effects are atomic: a bundle is fully validated in a temp
/// directory before it is moved into `pluginsDir`.
@MainActor
final class PluginInstaller {
    // `HTTPClient` is a plain (non-Sendable) protocol; conformers used here
    // (URLSessionHTTPClient, test stubs) are immutable value types, so a
    // stored `let` is safe to hand across the actor boundary for the await
    // (same pattern as `CatalogService.source`).
    private nonisolated(unsafe) let http: HTTPClient
    private let unzipper: Unzipper
    private let pluginsDir: URL
    private let pluginDataDir: URL
    private let retainedDataDir: URL
    private let persistence: PersistenceStore
    private let registry: BuiltInAppRegistry
    // `loadBundle` is a plain (non-Sendable) closure type; the only await in
    // `install` happens before it is used, so a stored `let` crossing the
    // actor boundary is safe (same pattern as `CatalogService.source`).
    private nonisolated(unsafe) let loadBundle: (URL) -> Result<RegisteredApp, PluginRejection>

    init(http: HTTPClient, unzipper: Unzipper, pluginsDir: URL, pluginDataDir: URL,
         retainedDataDir: URL, persistence: PersistenceStore, registry: BuiltInAppRegistry,
         loadBundle: @escaping (URL) -> Result<RegisteredApp, PluginRejection>) {
        self.http = http; self.unzipper = unzipper
        self.pluginsDir = pluginsDir; self.pluginDataDir = pluginDataDir
        self.retainedDataDir = retainedDataDir
        self.persistence = persistence; self.registry = registry; self.loadBundle = loadBundle
    }

    func install(_ entry: CatalogEntry) async throws {
        // 1. Download.
        let data: Data
        do { data = try await http.get(entry.downloadURL) }
        catch { throw AppStoreError.download(String(describing: error)) }

        // 2. Compute integrity digest (compared via StorePolicy in step 4,
        //    alongside the other store-review checks).
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        // 3. Unpack into a temp dir.
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: work) }
        let zip = work.appendingPathComponent("dl.zip")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        do { try data.write(to: zip); try unzipper.unzip(zip, to: work.appendingPathComponent("x")) }
        catch { throw AppStoreError.unpack(String(describing: error)) }

        // 4. Locate the bundle root and validate it (metadata + appID matches
        //    entry). `DittoUnzipper` (used both here and by the tooling that
        //    creates archives, per `ditto -c -k <dir>`'s documented behavior)
        //    unzips a directory's CONTENTS, not the directory itself — so the
        //    extracted root normally IS the bundle (Contents/Info.plist sits
        //    directly under it). Fall back to a `.bundle`-suffixed child for
        //    archives that do wrap the bundle in a top-level folder.
        let unpacked = work.appendingPathComponent("x")
        func readMetadata(at url: URL) -> (PluginBundleMetadata, [String: Any])? {
            guard let info = Bundle(url: url)?.infoDictionary,
                  case .success(let m) = PluginBundleMetadata.parse(infoDictionary: info) else { return nil }
            return (m, info)
        }
        let bundleURL: URL
        let metadata: PluginBundleMetadata
        let infoDict: [String: Any]
        if let (m, info) = readMetadata(at: unpacked) {
            bundleURL = unpacked; metadata = m; infoDict = info
        } else if let child = (try? FileManager.default.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil))?
            .first(where: { $0.pathExtension == "bundle" }), let (m, info) = readMetadata(at: child) {
            bundleURL = child; metadata = m; infoDict = info
        } else {
            throw AppStoreError.invalidBundle("no readable .bundle in archive")
        }
        guard metadata.appID == entry.appID else { throw AppStoreError.invalidBundle("appID mismatch") }

        // Same StorePolicy the store review / CLI run, so "passes review" is
        // defined by one shared authority (host, store, and CLI all agree).
        let manifest = StoreManifestInput(
            metadata: metadata, infoDictionary: infoDict,
            author: entry.author, description: entry.description, iconSymbol: entry.icon,
            declaredSHA256: entry.sha256, computedSHA256: digest)
        var issues = StorePolicy.check(manifest: manifest, minSupported: GenerationSupport.minSupported, current: GenerationSupport.current)
        // Grandfather legacy catalog entries published before store-listing
        // completeness existed: an entry whose manifest carried no `author` at
        // all (`author == nil`) predates the author/description requirement, so
        // refreshing or installing it must not newly fail on those listing
        // fields. Integrity, generation, icon, and base-metadata checks still
        // apply. `ainkrad publish` now refuses to publish any bundle that
        // fails StorePolicy (author/description required), so a NEW
        // submission can never reach the catalog author-less — a nil author
        // here can only mean a genuinely legacy entry, never a submission
        // that skipped the check.
        if entry.author == nil {
            issues.removeAll { $0.code == "missing-author" || $0.code == "missing-description" }
        }
        if let first = issues.first { throw AppStoreError.invalidBundle(first.message) }

        // 5. Atomic move into place (replace any prior install).
        let dest = pluginsDir.appendingPathComponent("\(entry.appID).bundle")
        try FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: bundleURL, to: dest)

        // 6. Record installed state.
        var doc = persistence.load(InstalledPluginsDocument.self) ?? InstalledPluginsDocument()
        doc.installed[entry.appID] = .init(version: entry.version, sourceRepo: entry.sourceRepo)
        persistence.save(doc)

        // 7. Register live (best-effort — install succeeds even if a relaunch is
        //    needed to load; the files + state are already committed).
        if case .success(let app) = loadBundle(dest) { registry.register(app) }
        else { Log.appStore.error("Installed \(entry.appID, privacy: .public) but live-load failed; effective next launch") }
    }

    /// Installs only if `entry.version` is newer than the installed version.
    func update(_ entry: CatalogEntry) async throws {
        let doc = persistence.load(InstalledPluginsDocument.self) ?? InstalledPluginsDocument()
        if let current = doc.installed[entry.appID], !PluginVersion.isNewer(entry.version, than: current.version) {
            throw AppStoreError.notNewer
        }
        try await install(entry)
    }

    /// Removes the installed bundle and installed-state entry, deregisters the
    /// app, and RETAINS its scoped data (moved to the retained area) so a
    /// reinstall can restore it. Retained data is kept until a Reset on reinstall.
    /// The already-loaded dylib is not unloaded (dyld limitation) — the app
    /// disappears from the list; its code lingers until the next launch.
    func uninstall(appID: String) throws {
        var doc = persistence.load(InstalledPluginsDocument.self) ?? InstalledPluginsDocument()
        guard doc.installed[appID] != nil else { throw AppStoreError.notInstalled(appID) }
        try? FileManager.default.removeItem(at: pluginsDir.appendingPathComponent("\(appID).bundle"))
        retainData(appID: appID)
        doc.installed[appID] = nil
        persistence.save(doc)
        registry.deregister(id: appID)
    }

    /// True when uninstalled data is being kept for `appID`.
    func hasRetainedData(appID: String) -> Bool {
        FileManager.default.fileExists(atPath: retainedDataDir.appendingPathComponent(appID).path)
    }

    /// Moves retained data back into the live scoped location (replacing any
    /// live data). Best-effort; no-op if nothing is retained.
    func restoreRetainedData(appID: String) {
        let retained = retainedDataDir.appendingPathComponent(appID)
        guard FileManager.default.fileExists(atPath: retained.path) else { return }
        let live = pluginDataDir.appendingPathComponent(appID)
        try? FileManager.default.createDirectory(at: pluginDataDir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: live)
        do {
            try FileManager.default.moveItem(at: retained, to: live)
        } catch {
            Log.appStore.error("Failed to move retained data for \(appID, privacy: .public) into \(live.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Permanently deletes retained data for `appID`. Best-effort.
    func discardRetainedData(appID: String) {
        try? FileManager.default.removeItem(at: retainedDataDir.appendingPathComponent(appID))
    }

    /// Moves live scoped data into the retained area, replacing any stale
    /// retained copy. No-op if the plugin never wrote data.
    private func retainData(appID: String) {
        let live = pluginDataDir.appendingPathComponent(appID)
        guard FileManager.default.fileExists(atPath: live.path) else { return }
        let retained = retainedDataDir.appendingPathComponent(appID)
        try? FileManager.default.createDirectory(at: retainedDataDir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: retained)
        do {
            try FileManager.default.moveItem(at: live, to: retained)
        } catch {
            Log.appStore.error("Failed to move live data for \(appID, privacy: .public) into retained storage: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Total, numeric dot-segment version comparison ("1.2" == "1.2.0"; missing
/// segments are 0). Non-numeric segments compare as 0.
enum PluginVersion {
    static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        let a = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let b = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
