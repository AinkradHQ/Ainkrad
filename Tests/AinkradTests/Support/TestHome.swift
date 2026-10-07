import AinkradAppKit
import Foundation

/// A throwaway Home plus an isolated defaults suite. Every test that bootstraps
/// must use this — it is what keeps the suite out of the developer's real data.
enum TestHome {
    static func make(_ label: String = "t") -> (home: Home, defaults: UserDefaults, cleanup: () -> Void) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        let vault = base.appendingPathComponent("vault", isDirectory: true)
        let cache = base.appendingPathComponent("cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)

        let suiteName = "com.ainkrad.tests.\(label).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        return (
            Home(vaultRoot: vault, cacheRoot: cache), defaults,
            {
                defaults.removePersistentDomain(forName: suiteName)
                try? FileManager.default.removeItem(at: base)
            }
        )
    }
}
