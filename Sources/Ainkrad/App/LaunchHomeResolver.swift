import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Resolves the Home at launch.
///
/// There is **no default Home location**. On first run the user picks the folder;
/// nothing is ever chosen on their behalf, because a location chosen for them is
/// how the app ends up planted in the middle of a directory that already belongs
/// to something else. `.missing` and `.foreign` throw rather than falling back to a
/// fresh vault — the exact failure this design forbids. `resolveWithRecovery`
/// then turns those throws into an alert the user can act on, so "never pick a
/// location for them" does not have to mean "crash on every launch".
///
/// This is the setup wizard's folder-choice step arriving early; the wizard plan
/// builds on it rather than replacing it.
enum LaunchHomeResolver {
    enum Failure: Error, Equatable {
        case vaultMissing(path: String)
        case notAnAinkradHome(path: String)
        /// The user dismissed the folder chooser without picking. Not an error in
        /// the crash sense — the app simply has no Home and must not invent one.
        case setupCancelled
        /// A `Resolution` case added by a newer AinkradAppKit than this host knows.
        /// `Resolution` is resilient (library evolution), so this is reachable.
        /// Throwing is the only safe answer: an unknown outcome must never be
        /// treated as "unset" and adopted over.
        case unrecognizedResolution
        /// The user chose Quit from a recovery alert. Like `setupCancelled` this
        /// is a decision, not a crash: nothing is written and the app exits 0.
        case userQuit
    }

    /// Asks the user for a folder. Returns `nil` if they cancelled.
    ///
    /// Injected so the resolver is testable without a modal panel; production
    /// passes `presentFolderChooser`.
    typealias VaultChooser = () -> URL?

    static func resolveOrAdopt(
        chooseVault: VaultChooser = LaunchHomeResolver.presentFolderChooser,
        pointerDirectory: URL = defaultHostPointerDirectory(),
        cacheRoot: URL = defaultHostCacheRoot(),
        // Injected so a test never touches — let alone marks as migrated — the real
        // machine's legacy container. `nil` means "nothing to migrate".
        legacyContainer: URL? = VaultMigration.legacyContainerURL()
    ) throws -> Home {
        switch AinkradHome.resolve(pointerDirectory: pointerDirectory, cacheRoot: cacheRoot) {
        case .ready(let home):
            return home

        case .missing(let path):
            throw Failure.vaultMissing(path: path)

        case .foreign(let url):
            throw Failure.notAnAinkradHome(path: url.path)

        case .unset:
            #if DEBUG
            if let roots = debugFixtureRoots {
                // Never migrate (and so never rename) the real machine's legacy container
                // into a fixture — `legacyContainerURL()` is already nil in fixture mode;
                // passing nil here makes it independent of what a caller injected.
                let home = try adopt(roots.defaultVaultRoot,
                                     pointerDirectory: pointerDirectory,
                                     cacheRoot: cacheRoot,
                                     legacyContainer: nil)
                seedDebugFixtureIfNeeded(home: home)
                return home
            }
            #endif
            guard let chosen = chooseVault() else { throw Failure.setupCancelled }
            return try adopt(chosen,
                             pointerDirectory: pointerDirectory,
                             cacheRoot: cacheRoot,
                             legacyContainer: legacyContainer)

        @unknown default:
            throw Failure.unrecognizedResolution
        }
    }

    /// Claims `chosen` as the Home: validate → marker → migrate → adopt → mark.
    ///
    /// Split out of `resolveOrAdopt` so the recovery path can re-run exactly this
    /// sequence against a folder the user picked after a `.missing`/`.foreign`
    /// pointer, without going back through `resolve()` — which would just throw
    /// the same error again.
    static func adopt(
        _ chosen: URL,
        pointerDirectory: URL,
        cacheRoot: URL,
        legacyContainer: URL?
    ) throws -> Home {
        let home = Home(vaultRoot: chosen, cacheRoot: cacheRoot)

        // Validate BEFORE migrating. `adopt` refuses a populated directory, and
        // discovering that only after copying gigabytes into it would leave the
        // user's chosen folder littered by a run that then failed.
        try AinkradHome.validate(chosen)

        // Write the marker before migrating, for two reasons. First, migration
        // populates the folder, so the `adopt` below would otherwise be refused
        // by its own emptiness rule. Second — and this is the one that matters —
        // if migration fails part-way, the folder is left non-empty; without a
        // marker the user could never choose it again, because every retry would
        // be refused as `.notEmpty`. The marker is identity only; the POINTER is
        // still what claims a vault as authoritative, and it is still written
        // last. `read ?? new` keeps reinstall-and-restore's homeID intact.
        try (HomeMarker.read(in: chosen) ?? HomeMarker()).write(to: chosen)

        // Migrate BEFORE adopting. `adopt` is what writes the pointer, and a
        // pointer is the app's claim that this vault is authoritative. If the
        // copy fails part-way, no pointer exists, so the next launch is a clean
        // first run over the same untouched legacy tree — the guarantee
        // VaultMigration is built around. Adopting first would leave a pointer
        // to a half-populated vault that never gets migrated again.
        var migration: (container: URL, report: VaultMigration.Report)?
        if let container = legacyContainer,
           VaultMigration.needsMigration(container: container) {
            migration = (container, try VaultMigration.migrate(fromContainer: container, into: home))
        }

        // `adopt` writes the marker and pointer; it returns an equivalent Home.
        let adopted = try AinkradHome.adopt(chosen,
                                            pointerDirectory: pointerDirectory,
                                            cacheRoot: cacheRoot)

        // ONLY NOW rename the legacy tree. Between a verified copy and a durable
        // pointer there is a window in which `adopt` can still throw — the pointer
        // write itself, or the `cacheRoot` createDirectory, and disk-full is
        // exactly the failure a large migration provokes. If the rename had
        // already happened, that throw would leave no pointer (so the next launch
        // is `.unset`), the user would pick a different folder, and the marker
        // would make `needsMigration` answer false — adopting the new folder empty
        // while the whole dataset sat in the first one under a name it no longer
        // had, with no signal to the user at all. Marking last closes that window:
        // a failure anywhere above leaves the legacy tree under its ORIGINAL name,
        // so the next launch simply re-migrates.
        //
        // Best-effort, not `try`: the pointer is already written, so a failed
        // rename cannot strand anything — the vault is authoritative and the
        // legacy tree is merely a lingering duplicate. Throwing here would put a
        // failure alert in front of a setup that actually succeeded.
        if let migration {
            do {
                try VaultMigration.markMigrated(container: migration.container,
                                                report: migration.report)
            } catch {
                Log.persistence.error(
                    "Migration completed but the legacy tree could not be marked: \(error.localizedDescription, privacy: .public)")
            }
        }
        return adopted
    }

    /// Resolves the Home, and when that fails, tells the user what happened and
    /// lets them act — instead of crashing on every launch with no way back.
    ///
    /// The failures this exists for are ordinary, not exotic: a vault on an
    /// external or network volume that is not mounted yet (`.missing`), a vault
    /// copied between Macs so the `homeID` no longer matches (`.foreign`), and —
    /// most likely of all — picking a folder that already has files in it on
    /// first run (`HomeError.notEmpty`; the panel opens on the user's home
    /// directory, so `~/Documents` is one click away). Before this, every one of
    /// those was a `fatalError` whose only escape was hand-deleting a file in
    /// `~/Library/Application Support/Ainkrad`.
    ///
    /// This does NOT relax the no-fallback rule. The app still never picks a
    /// location; the only way forward is a folder the user chooses, and the only
    /// other option is quitting.
    ///
    /// `present` is injected so the decision logic is testable without a modal —
    /// the same seam `chooseVault` already uses.
    static func resolveWithRecovery(
        chooseVault: VaultChooser = LaunchHomeResolver.presentFolderChooser,
        present: (LaunchRecovery.Prompt) -> LaunchRecovery.Action = LaunchHomeResolver.presentAlert,
        pointerDirectory: URL = defaultHostPointerDirectory(),
        cacheRoot: URL = defaultHostCacheRoot(),
        legacyContainer: URL? = VaultMigration.legacyContainerURL()
    ) throws -> Home {
        // Set once the user picks a folder from a recovery alert. It bypasses
        // `resolve()`, which would only re-throw the same `.missing`/`.foreign`
        // that got us here — the user's explicit choice is what re-points the app.
        var recoveryChoice: URL?

        while true {
            do {
                if let chosen = recoveryChoice {
                    recoveryChoice = nil
                    return try adopt(chosen, pointerDirectory: pointerDirectory,
                                     cacheRoot: cacheRoot, legacyContainer: legacyContainer)
                }
                return try resolveOrAdopt(chooseVault: chooseVault,
                                          pointerDirectory: pointerDirectory,
                                          cacheRoot: cacheRoot,
                                          legacyContainer: legacyContainer)
            } catch Failure.setupCancelled {
                throw Failure.setupCancelled
            } catch {
                guard let prompt = LaunchRecovery.prompt(for: error) else { throw error }
                switch present(prompt) {
                case .quit:
                    throw Failure.userQuit
                case .chooseFolder:
                    guard let chosen = chooseVault() else { throw Failure.setupCancelled }
                    recoveryChoice = chosen
                }
            }
        }
    }

    /// The production `present`: a modal alert, before any window exists.
    static func presentAlert(_ prompt: LaunchRecovery.Prompt) -> LaunchRecovery.Action {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = prompt.title
        alert.informativeText = prompt.message
        for title in prompt.buttons { alert.addButton(withTitle: title) }

        let index = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard prompt.actions.indices.contains(index) else { return .quit }
        return prompt.actions[index]
    }

    /// True when this process is hosting a test bundle rather than a real launch.
    ///
    /// The environment variable ALONE, deliberately. A `NSClassFromString("XCTestCase")`
    /// probe would also answer true in any shipped build that ever linked XCTest —
    /// and a release app that believes it is under test silently runs on
    /// `provisionalHome()`, writing every authored byte to a temporary
    /// directory the OS deletes. The env var is set by the test runner and by
    /// nothing else.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// A disposable Home under the temporary directory. Never adopted, so no
    /// pointer is written and no real vault is claimed.
    ///
    /// Two callers, one behaviour. The test host uses it to stay inert; first-run
    /// setup uses it so the full environment boots — island, workspaces, the lot —
    /// behind the setup gate, on a Home the user has not chosen yet. Because it is
    /// under the temporary directory it is `isProvisional`, so nothing the user
    /// authors (and above all no secret) may be written to it: see
    /// `Home+KeychainService.swift`. Task 4's adoption swaps it out in-session.
    static func provisionalHome() -> Home {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ainkrad-provisional-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return Home(vaultRoot: base.appendingPathComponent("vault", isDirectory: true),
                    cacheRoot: base.appendingPathComponent("cache", isDirectory: true))
    }

    /// The first-run folder chooser.
    ///
    /// Runs during `App.init`, before any window exists. `NSApplication.shared` is
    /// already instantiated by then (SwiftUI creates it before running the `App`
    /// initialiser), and `NSOpenPanel.runModal` spins up its own modal session with
    /// its own window, so it does not need a host window. It DOES need the process
    /// to be frontmost, or the panel opens behind whatever the user was looking at
    /// with no Dock click able to raise it — hence the explicit activation.
    static func presentFolderChooser() -> URL? {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a folder for your Ainkrad Home. "
            + "Pick an empty folder, or create a new one — Ainkrad will not take over "
            + "a folder that already has files in it."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        return panel.runModal() == .OK ? panel.url : nil
    }
}
