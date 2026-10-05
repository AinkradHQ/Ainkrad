import Foundation
import os
import AinkradAppKit
import AinkradHostRuntime

/// Key-value argument lookup closure type.
typealias ArgumentLookup = @Sendable (String) -> String?

#if DEBUG
/// Parsed fixture root paths resolved once at launch in DEBUG builds.
struct DebugFixtureRoots {
    let pointerDirectory: URL
    let cacheRoot: URL
    let defaultVaultRoot: URL
}

/// Parses `-AinkradOpenApp <appID>` and optional `-AinkradOpenAppPayload <payload>` using a key-value lookup.
func parseDebugOpenAppArguments(_ value: ArgumentLookup = { UserDefaults.standard.string(forKey: $0) }) -> (appID: String, payload: String?)? {
    guard let rawAppID = value("AinkradOpenApp") else { return nil }
    let appID = rawAppID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !appID.isEmpty else { return nil }
    let rawPayload = value("AinkradOpenAppPayload")?.trimmingCharacters(in: .whitespacesAndNewlines)
    let payload = (rawPayload?.isEmpty ?? true) ? nil : rawPayload
    return (appID, payload)
}

/// Parses `-AinkradOpenGallery 1` using a key-value lookup.
/// Returns true if the flag is set to "1" or "true".
func parseDebugOpenGalleryArgument(_ value: ArgumentLookup = { UserDefaults.standard.string(forKey: $0) }) -> Bool {
    guard let rawValue = value("AinkradOpenGallery") else { return false }
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return trimmed == "1" || trimmed == "true"
}

/// Parses `-AinkradGalleryTheme <themeID>` using a key-value lookup.
/// Returns the matching Theme, or nil if missing or invalid. Logs if invalid.
func parseDebugGalleryThemeArgument(_ value: ArgumentLookup = { UserDefaults.standard.string(forKey: $0) }) -> Theme? {
    guard let rawThemeID = value("AinkradGalleryTheme") else { return nil }
    let themeID = rawThemeID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !themeID.isEmpty else { return nil }
    if let theme = Theme(rawValue: themeID) {
        return theme
    } else {
        Log.app.error("DEBUG launch arg: unknown AinkradGalleryTheme '\(themeID, privacy: .public)'")
        return nil
    }
}

/// Parses `-AinkradGallerySection <id>` using a key-value lookup.
/// Returns the section id string, or nil if absent or empty.
func parseDebugGallerySectionArgument(_ value: ArgumentLookup = { UserDefaults.standard.string(forKey: $0) }) -> String? {
    guard let rawSection = value("AinkradGallerySection") else { return nil }
    let section = rawSection.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !section.isEmpty else { return nil }
    return section
}

/// Parses `-AinkradFixtureSeed 1` using a key-value lookup.
/// Returns true if the flag is set to "1" or "true".
func parseDebugFixtureSeedArgument(_ value: ArgumentLookup = { UserDefaults.standard.string(forKey: $0) }) -> Bool {
    guard let rawValue = value("AinkradFixtureSeed") else { return false }
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return trimmed == "1" || trimmed == "true"
}

/// Seeds a fixture vault with complete first-run setup state if -AinkradFixtureSeed 1 is passed
/// together with -AinkradFixtureRoot. If -AinkradFixtureSeed is supplied without -AinkradFixtureRoot,
/// logs an error and ignores it (never seeds a real Home).
func seedDebugFixtureIfNeeded(home: Home?, lookup: ArgumentLookup = { UserDefaults.standard.string(forKey: $0) }) {
    let shouldSeed = parseDebugFixtureSeedArgument(lookup)
    guard shouldSeed else { return }
    guard let home = home else {
        Log.app.error("DEBUG launch arg: -AinkradFixtureSeed passed without -AinkradFixtureRoot; ignoring.")
        return
    }

    let vaultConfigURL = home.vaultRoot.appendingPathComponent("Config", isDirectory: true)
    let persistence = FileDocumentStore(rootURL: vaultConfigURL)
    
    if persistence.load(SetupDocument.self) == nil {
        let setupDoc = SetupDocument(
            completedAt: Date(timeIntervalSince1970: 0),
            setupVersion: 1,
            deferredSteps: []
        )
        persistence.save(setupDoc)
    }

    if persistence.load(GlobalSettings.self) == nil {
        persistence.save(GlobalSettings())
    }
}

/// Parses `-AinkradFixtureRoot <path>` using a key-value lookup.
/// Returns the standardized URL for the directory, or nil if not provided or empty.
func parseDebugFixtureRootArgument(_ value: ArgumentLookup = { UserDefaults.standard.string(forKey: $0) }) -> URL? {
    guard let rawPath = value("AinkradFixtureRoot") else { return nil }
    let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !path.isEmpty else { return nil }
    return URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
}

/// Why a fixture root was refused.
enum DebugFixtureRootError: Error, Equatable {
    case notAWritableDirectory(String)
    case cannotCreate(String)
}

/// Resolves `-AinkradFixtureRoot <path>` and creates its `Pointer/`, `Cache/` and `Vault/`
/// subdirectories. `nil` when the argument is absent. Throws instead of exiting so a test can
/// drive it; the launch-time decision to refuse lives in `debugFixtureRoots` below.
///
/// `Vault/` must exist before `LaunchHomeResolver.adopt` validates it — `AinkradHome.validate`
/// throws `.doesNotExist` for a missing folder, which used to drop the launch into the
/// recovery alert and leave a fixture host waiting on a modal.
func resolveDebugFixtureRoots(_ value: ArgumentLookup) throws -> DebugFixtureRoots? {
    guard let fixtureURL = parseDebugFixtureRootArgument(value) else { return nil }
    let fm = FileManager.default
    var isDir: ObjCBool = false
    if fm.fileExists(atPath: fixtureURL.path, isDirectory: &isDir) {
        guard isDir.boolValue, fm.isWritableFile(atPath: fixtureURL.path) else {
            throw DebugFixtureRootError.notAWritableDirectory(fixtureURL.path)
        }
    }
    let roots = DebugFixtureRoots(
        pointerDirectory: fixtureURL.appendingPathComponent("Pointer", isDirectory: true),
        cacheRoot: fixtureURL.appendingPathComponent("Cache", isDirectory: true),
        defaultVaultRoot: fixtureURL.appendingPathComponent("Vault", isDirectory: true)
    )
    do {
        for directory in [roots.pointerDirectory, roots.cacheRoot, roots.defaultVaultRoot] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    } catch {
        throw DebugFixtureRootError.cannotCreate(fixtureURL.path)
    }
    return roots
}

/// The fixture roots for this process, resolved exactly once (a global `let` is initialized
/// lazily and atomically on first access). A fixture path that cannot be used refuses the
/// launch: falling back to the real Home is the one outcome this flag exists to prevent.
let debugFixtureRoots: DebugFixtureRoots? = {
    do {
        let lookup: ArgumentLookup = { UserDefaults.standard.string(forKey: $0) }
        return try resolveDebugFixtureRoots(lookup)
    } catch {
        Log.app.error("DEBUG fixture root refused: \(String(describing: error), privacy: .public)")
        fputs("Ainkrad [DEBUG]: refusing to start — fixture root unusable: \(error)\n", stderr)
        exit(1)
    }
}()
#endif

/// The host pointer directory: the fixture's `Pointer/` in a DEBUG fixture launch, else the default.
func defaultHostPointerDirectory() -> URL {
    #if DEBUG
    if let roots = debugFixtureRoots { return roots.pointerDirectory }
    #endif
    return AinkradHome.defaultPointerDirectory()
}

/// The host cache root: the fixture's `Cache/` in a DEBUG fixture launch, else the default.
func defaultHostCacheRoot(bundleID: String = Bundle.main.bundleIdentifier ?? "com.ainkrad.app") -> URL {
    #if DEBUG
    if let roots = debugFixtureRoots { return roots.cacheRoot }
    #endif
    return AinkradHome.defaultCacheRoot(bundleID: bundleID)
}

/// The hosted App Store catalog (the central AinkradCatalog).
let remoteCatalogURL = URL(string: "https://raw.githubusercontent.com/AinkradHQ/AinkradCatalog/main/catalog.json")!

/// The App Store catalog location: `<fixture root>/catalog.json` in a DEBUG fixture launch
/// (no network, identical content in every capture; a missing file just leaves the store
/// empty/offline), else the hosted catalog.
func defaultHostCatalogURL() -> URL {
    #if DEBUG
    if let roots = debugFixtureRoots { return fixtureCatalogURL(in: roots) }
    #endif
    return remoteCatalogURL
}

#if DEBUG
/// `catalog.json` beside the fixture's `Pointer/`, `Cache/` and `Vault/`.
func fixtureCatalogURL(in roots: DebugFixtureRoots) -> URL {
    roots.cacheRoot.deletingLastPathComponent().appendingPathComponent("catalog.json")
}
#endif
