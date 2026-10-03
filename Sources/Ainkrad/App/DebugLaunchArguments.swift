import Foundation
import os
import AinkradAppKit

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

/// Parses `-AinkradFixtureRoot <path>` using a key-value lookup.
/// Returns the standardized URL for the directory, or nil if not provided or empty.
func parseDebugFixtureRootArgument(_ value: ArgumentLookup = { UserDefaults.standard.string(forKey: $0) }) -> URL? {
    guard let rawPath = value("AinkradFixtureRoot") else { return nil }
    let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !path.isEmpty else { return nil }
    return URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
}

/// Resolves and validates `-AinkradFixtureRoot <path>` ONCE at launch.
///
/// Returns `DebugFixtureRoots` containing subdirectories under the fixture root if provided,
/// or `nil` if `-AinkradFixtureRoot` was not supplied.
/// If the path is specified but is invalid or unwritable, logs an error to `Log.app.error` and `stderr`,
/// and terminates the process with `exit(1)` (refusing to fall back silently).
func resolveDebugFixtureRoots(_ value: ArgumentLookup = { UserDefaults.standard.string(forKey: $0) }) -> DebugFixtureRoots? {
    guard let fixtureURL = parseDebugFixtureRootArgument(value) else { return nil }

    var isDir: ObjCBool = false
    let fm = FileManager.default
    if fm.fileExists(atPath: fixtureURL.path, isDirectory: &isDir) {
        if !isDir.boolValue || !fm.isWritableFile(atPath: fixtureURL.path) {
            Log.app.error("DEBUG fixture root path exists but is not a writable directory: \(fixtureURL.path, privacy: .public)")
            fputs("Ainkrad [DEBUG]: Refusing to start — fixture root \(fixtureURL.path) is not a writable directory.\n", stderr)
            exit(1)
        }
    } else {
        do {
            try fm.createDirectory(at: fixtureURL, withIntermediateDirectories: true)
        } catch {
            Log.app.error("DEBUG fixture root directory could not be created at \(fixtureURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            fputs("Ainkrad [DEBUG]: Refusing to start — fixture root directory could not be created at \(fixtureURL.path): \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    return DebugFixtureRoots(
        pointerDirectory: fixtureURL.appendingPathComponent("Pointer", isDirectory: true),
        cacheRoot: fixtureURL.appendingPathComponent("Cache", isDirectory: true),
        defaultVaultRoot: fixtureURL.appendingPathComponent("Vault", isDirectory: true)
    )
}
#endif

/// Resolves the host pointer directory. In DEBUG builds, checks `-AinkradFixtureRoot <path>`.
func defaultHostPointerDirectory(value: ArgumentLookup = { UserDefaults.standard.string(forKey: $0) }) -> URL {
    #if DEBUG
    if let roots = resolveDebugFixtureRoots(value) {
        return roots.pointerDirectory
    }
    #endif
    return AinkradHome.defaultPointerDirectory()
}

/// Resolves the host cache root. In DEBUG builds, checks `-AinkradFixtureRoot <path>`.
func defaultHostCacheRoot(value: ArgumentLookup = { UserDefaults.standard.string(forKey: $0) }, bundleID: String = Bundle.main.bundleIdentifier ?? "com.ainkrad.app") -> URL {
    #if DEBUG
    if let roots = resolveDebugFixtureRoots(value) {
        return roots.cacheRoot
    }
    #endif
    return AinkradHome.defaultCacheRoot(bundleID: bundleID)
}

