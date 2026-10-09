import AinkradHostRuntime
import CryptoKit
import Foundation

/// Installed store themes and colour schemes, kept apart from
/// `InstalledPluginsDocument` so a theme id never collides with an app id.
struct InstalledThemesDocument: PersistableDocument {
    static let documentID = "installed-themes"

    struct Entry: Codable, Equatable {
        let version: String
        let kind: ThemeCatalogEntry.Kind
        let files: [String]
    }
    var installed: [String: Entry] = [:]  // keyed by entry id
}

/// Installs, updates and removes store themes and colour schemes into
/// `<Home>/Config/Themes/Store/<id>/`, then reloads the theme catalog so the
/// change is live without a restart. Follows `SkillInstaller`: the id is checked
/// before any filesystem call, and every file is sha-checked and trial-loaded
/// before anything lands in the store folder.
@MainActor
final class ThemeInstaller {
    // Same non-Sendable `HTTPClient` pattern as `SkillInstaller`.
    private nonisolated(unsafe) let http: HTTPClient
    private let storeRoot: URL
    private let persistence: PersistenceStore
    private let themeManager: ThemeManager

    /// - Parameter storeRoot: `<Home>/Config/Themes/Store`, inside a root the theme catalog scans.
    init(http: HTTPClient, storeRoot: URL, persistence: PersistenceStore, themeManager: ThemeManager) {
        self.http = http
        self.storeRoot = storeRoot
        self.persistence = persistence
        self.themeManager = themeManager
    }

    /// Installs `entry`, or replaces an installed copy (an update). Throws
    /// `AppStoreError.invalidBundle` with the problems, one per line, on refusal.
    func install(_ entry: ThemeCatalogEntry) async throws {
        guard SkillValidator.isSafeName(entry.id) else {
            throw AppStoreError.invalidBundle("unsafe theme id \(entry.id)")
        }
        guard entry.isCompatible else {
            throw AppStoreError.invalidBundle("\(entry.id) needs theme format \(entry.format)")
        }
        let names = try Self.fileNames(of: entry)

        var payloads: [(name: String, data: Data)] = []
        for (file, name) in zip(entry.files, names) {
            let data: Data
            do { data = try await http.get(file.url) } catch {
                throw AppStoreError.download(String(describing: error))
            }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == file.sha256.lowercased() else { throw AppStoreError.checksumMismatch }
            payloads.append((name, data))
        }

        let fm = FileManager.default
        let trial = fm.temporaryDirectory.appendingPathComponent("theme-trial-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: trial) }
        try fm.createDirectory(at: trial, withIntermediateDirectories: true)
        for payload in payloads { try payload.data.write(to: trial.appendingPathComponent(payload.name)) }
        let problems = themeManager.catalog.trialProblems(entryID: entry.id, isTheme: entry.kind == .theme, staged: trial)
        guard problems.isEmpty else { throw AppStoreError.invalidBundle(problems.joined(separator: "\n")) }

        // A hidden sibling (the catalog skips hidden folders), then one swap into place.
        try fm.createDirectory(at: storeRoot, withIntermediateDirectories: true)
        let staging = storeRoot.appendingPathComponent(".\(entry.id)-\(UUID().uuidString)", isDirectory: true)
        let destination = storeRoot.appendingPathComponent(entry.id, isDirectory: true)
        do {
            try fm.copyItem(at: trial, to: staging)
            if fm.fileExists(atPath: destination.path) {
                _ = try fm.replaceItemAt(destination, withItemAt: staging)
            } else {
                try fm.moveItem(at: staging, to: destination)
            }
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }

        var doc = persistence.load(InstalledThemesDocument.self) ?? InstalledThemesDocument()
        doc.installed[entry.id] = .init(version: entry.version, kind: entry.kind, files: names)
        persistence.save(doc)
        themeManager.reloadCatalog()
    }

    /// Removes an installed entry's folder and record. An active theme or scheme
    /// falls back (its stored id is kept, so a reinstall restores it).
    func uninstall(id: String) throws {
        guard SkillValidator.isSafeName(id) else { throw AppStoreError.invalidBundle("unsafe theme id \(id)") }
        var doc = persistence.load(InstalledThemesDocument.self) ?? InstalledThemesDocument()
        guard doc.installed[id] != nil else { throw AppStoreError.notInstalled(id) }
        try? FileManager.default.removeItem(at: storeRoot.appendingPathComponent(id, isDirectory: true))
        doc.installed[id] = nil
        persistence.save(doc)
        themeManager.reloadCatalog()
    }

    /// The on-disk name of each file: `<safe-name>.theme|.scheme`, unique. A theme
    /// entry needs at least one `.theme`; a scheme entry exactly one `.scheme`.
    private static func fileNames(of entry: ThemeCatalogEntry) throws -> [String] {
        let names = entry.files.map(\.url.lastPathComponent)
        for name in names {
            let path = name as NSString
            guard ["theme", "scheme"].contains(path.pathExtension),
                SkillValidator.isSafeName(path.deletingPathExtension)
            else { throw AppStoreError.invalidBundle("unsafe theme file name \(name)") }
        }
        guard Set(names).count == names.count else {
            throw AppStoreError.invalidBundle("\(entry.id) lists a file name twice")
        }
        let themes = names.filter { $0.hasSuffix(".theme") }.count
        switch entry.kind {
        case .theme where themes == 0:
            throw AppStoreError.invalidBundle("theme \(entry.id) has no .theme file")
        case .colorScheme where names.count != 1 || themes != 0:
            throw AppStoreError.invalidBundle("colour scheme \(entry.id) must be exactly one .scheme file")
        default:
            return names
        }
    }
}
