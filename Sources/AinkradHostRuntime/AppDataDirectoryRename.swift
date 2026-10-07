import Foundation

/// One-time move of each retired app's data directory under `<vault>/Apps`.
///
/// Must run BEFORE any `HostServicesImpl` is constructed: that initialiser
/// hands `ScopedPluginDocumentStore` a `<root>/<appID>` URL, and a store
/// pointed at a fresh empty directory silently orphans the user's documents
/// rather than reporting anything.
///
/// Deliberately does not throw and does not delete. A rename that cannot
/// complete leaves both directories in place: the app starts empty, which is
/// visible and recoverable, rather than destroying state on a path we could
/// not reason about.
public enum AppDataDirectoryRename {
    public static func run(root: URL, fileManager: FileManager = .default) {
        guard fileManager.fileExists(atPath: root.path) else { return }
        for (old, new) in AppIDRenames.map {
            let source = root.appendingPathComponent(old, isDirectory: true)
            let destination = root.appendingPathComponent(new, isDirectory: true)
            guard fileManager.fileExists(atPath: source.path),
                !fileManager.fileExists(atPath: destination.path)
            else { continue }
            do {
                try fileManager.moveItem(at: source, to: destination)
                Log.persistence.info(
                    "Renamed app data \(old, privacy: .public) → \(new, privacy: .public)")
            } catch {
                Log.persistence.error(
                    "Could not rename app data \(old, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }
}
