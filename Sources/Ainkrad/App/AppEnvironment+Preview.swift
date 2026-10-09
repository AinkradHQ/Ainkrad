import AinkradAppKit
import AinkradHostRuntime
import Foundation
import SwiftUI

#if DEBUG
extension AppEnvironment {
    /// A fully-wired `AppEnvironment` for previews and tests that need real
    /// descriptor→store bindings (e.g. `HostSettingsCatalog`) without a real
    /// app launch. Each call gets its own temp directory and an isolated
    /// `UserDefaults` suite, so callers never see another call's state and
    /// nothing touches the developer's real `~/Library/Application Support`
    /// or `.standard` defaults. Reuses the production `bootstrap()` wiring
    /// rather than a bespoke stub graph — `LaunchHomeResolver.isRunningTests` already gates
    /// the network/TCC-prompting I/O (model probe, MCP connect, LSP
    /// autodetect) when hosted under `xcodebuild test`, so this is safe and
    /// fast in that context; call sites outside tests should expect that
    /// gating to relax and real I/O to occur.
    ///
    /// Cleanup is tied to the returned instance's lifetime (`deinit` below)
    /// rather than, say, a shared/reused environment, because reuse would
    /// mean two tests running back-to-back could observe each other's
    /// mutations — the exact cross-test contamination every later task's
    /// catalog tests depend on NOT happening. Per-call isolation is kept;
    /// only the on-disk/on-suite footprint is reclaimed, once the caller
    /// drops its last reference.
    ///
    /// `launchArguments` stands in for the DEBUG theme launch arguments, keyed without
    /// the dash (`["AinkradTheme": "glass", "AinkradThemesDir": dir]`), so an
    /// off-screen snapshot can pick a theme, scheme and appearance. The process's own
    /// arguments are never read here.
    static func preview(launchArguments: [String: String] = [:]) -> AppEnvironment {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AinkradPreview-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "com.ainkrad.preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        // A per-call temp vault, which is also what keeps `preview()` out of the
        // real Keychain: `Home.keychainServiceName` derives the Keychain service
        // from the vault path, so this throwaway vault gets a throwaway namespace
        // (see `Home+KeychainService.swift`). Several test suites use `preview()`,
        // so that is load-bearing, not incidental.
        let home = Home(
            vaultRoot: root.appendingPathComponent("vault", isDirectory: true),
            cacheRoot: root.appendingPathComponent("cache", isDirectory: true))
        let environment = bootstrap(home: home, defaults: defaults, launchArguments: { launchArguments[$0] })
        environment.previewTeardown = {
            try? FileManager.default.removeItem(at: root)
            UserDefaults().removePersistentDomain(forName: suiteName)
        }
        return environment
    }
}
#endif
