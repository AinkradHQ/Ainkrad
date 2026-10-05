import Foundation

/// Removes an installed plugin bundle whose app id was retired by the v0.16.0
/// rename.
///
/// `AppIDRenames` migrates the *documents* that key off an app id, but a
/// plugin's identity also lives inside its installed bundle: `PluginInstaller`
/// writes `<appID>.bundle`, and `PluginLoader` reads `AinkradAppID` back out of
/// each bundle's Info.plist. A v0.7.1 Terminal on disk is still literally
/// `terminal.bundle` declaring `AinkradAppID = terminal`, so without this the
/// loader registers the retired app alongside the new one — and because the
/// installer removes `<appID>.bundle`, installing Rune writes `rune.bundle`
/// and leaves `terminal.bundle` untouched. The user ends up running BOTH.
///
/// Deleting is safe and self-healing: plugin binaries are cache, not vault —
/// every one is re-downloadable from the catalog. The migrated
/// `installed-plugins` entry keeps its old version number, so the App Store
/// immediately offers the update that restores the app under its new id.
public enum RetiredPluginBundleCleanup {
    public static func run(pluginsDirectories: [URL], fileManager: FileManager = .default) {
        for directory in pluginsDirectories {
            guard fileManager.fileExists(atPath: directory.path) else { continue }
            for (old, new) in AppIDRenames.map {
                let retired = directory.appendingPathComponent("\(old).bundle", isDirectory: true)
                guard fileManager.fileExists(atPath: retired.path) else { continue }
                do {
                    try fileManager.removeItem(at: retired)
                    Log.persistence.info(
                        "Removed retired plugin bundle \(old, privacy: .public).bundle — reinstall as \(new, privacy: .public)"
                    )
                } catch {
                    Log.persistence.error(
                        "Could not remove retired plugin bundle \(old, privacy: .public).bundle: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }
    }
}
