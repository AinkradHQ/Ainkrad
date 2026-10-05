import AinkradHostRuntime
import Foundation

/// Installs / uninstalls skill catalog items. Skills are markdown assets: fetch
/// the SKILL.md, validate it, write it to Skills/<appID>/, and record installed
/// state so the App Store lists it. No download of executables, no `dlopen`.
///
/// `appID` becomes the on-disk directory name — the same value
/// `SkillRegistry`'s `marketplaceNames()` surfaces, so an installed skill loads
/// as `.marketplace`. It is checked with `SkillValidator.isSafeName` BEFORE any
/// `FileManager` operation, exactly like `SkillRegistry`'s `requireSafeName`, so
/// a malicious/traversal `appID` (`../../etc`, absolute paths, …) can never
/// escape the Skills root.
@MainActor
final class SkillInstaller {
    // `HTTPClient` is a plain (non-Sendable) protocol; conformers used here
    // (URLSessionHTTPClient, test stubs) are immutable value types, so a
    // stored `let` is safe to hand across the actor boundary for the await
    // (same pattern as `PluginInstaller`/`CatalogService`).
    private nonisolated(unsafe) let http: HTTPClient
    private let paths: SkillPaths
    private let persistence: PersistenceStore

    init(http: HTTPClient, paths: SkillPaths, persistence: PersistenceStore) {
        self.http = http
        self.paths = paths
        self.persistence = persistence
    }

    /// Fetches, validates, and installs a `.skill` catalog entry. Idempotent —
    /// installing the same entry twice simply overwrites the one file with the
    /// same (re-fetched) content and re-records the same installed-state entry;
    /// it never duplicates or corrupts what's on disk.
    func install(_ entry: CatalogEntry) async throws {
        guard entry.isValidSkillEntry, let descriptor = entry.skill else {
            throw AppStoreError.invalidBundle("invalid skill catalog entry \(entry.appID)")
        }
        // Guard the directory name BEFORE any filesystem operation — mirrors
        // SkillRegistry.requireSafeName. A catalog is semi-trusted at best.
        guard SkillValidator.isSafeName(entry.appID) else {
            throw AppStoreError.invalidBundle("unsafe skill appID \(entry.appID)")
        }

        let data: Data
        do { data = try await http.get(descriptor.contentURL) } catch {
            throw AppStoreError.download(String(describing: error))
        }

        let text = String(decoding: data, as: UTF8.self)

        // Validate before writing so a malformed/malicious asset never lands on
        // disk, even transiently.
        let parsed: Skill
        do { parsed = try SkillParser.parse(text, source: .marketplace) } catch {
            throw AppStoreError.invalidBundle("malformed SKILL.md for \(entry.appID): \(error)")
        }
        let issues = SkillValidator.validate(parsed)
        guard issues.isEmpty else {
            throw AppStoreError.invalidBundle("invalid SKILL.md for \(entry.appID): \(issues)")
        }

        let url = paths.skillFile(entry.appID)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)

        var doc = persistence.load(InstalledPluginsDocument.self) ?? InstalledPluginsDocument()
        doc.installed[entry.appID] = .init(version: entry.version, sourceRepo: entry.sourceRepo)
        persistence.save(doc)
    }

    /// Removes the installed skill directory and its installed-state entry.
    func uninstall(appID: String) throws {
        guard SkillValidator.isSafeName(appID) else {
            throw AppStoreError.invalidBundle("unsafe skill appID \(appID)")
        }
        var doc = persistence.load(InstalledPluginsDocument.self) ?? InstalledPluginsDocument()
        guard doc.installed[appID] != nil else { throw AppStoreError.notInstalled(appID) }
        try? FileManager.default.removeItem(at: paths.skillDir(appID))
        doc.installed[appID] = nil
        persistence.save(doc)
    }
}
