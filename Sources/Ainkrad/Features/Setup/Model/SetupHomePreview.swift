import AinkradAppKit
import Foundation

/// What the Home step shows the user is about to be created inside the folder
/// they pick.
///
/// The point of the screen is that the folder IS the idea: a user who is shown
/// a path field and a button is choosing a string, while a user who is shown
/// the shape of what will appear inside the folder is choosing a place for
/// their work to live. So this is not decoration — it is the explanation.
///
/// Every entry is anchored to a real `SharedDomain` rather than typed out, so
/// the screen cannot drift away from the layout the app actually writes.
///
/// The anchoring runs in BOTH directions, which is the only way the claim is
/// worth making:
///
/// - Names come from `Home.shared(_:)` and `Home.vault(app:)`, so no row can
///   promise a directory the app never creates.
/// - `entries` is generated from `SharedDomain.allCases` rather than typed out,
///   and `SetupHomeStepTests` asserts that every domain's top-level folder
///   appears in the listing — so a new shared domain fails the suite until
///   someone decides whether the user should be told about it.
///
/// The gate is a test rather than a `default`-free `switch` because
/// `SharedDomain` is non-frozen across the module boundary: the compiler
/// requires `@unknown default` regardless of how exhaustive `description(of:)`
/// is, which makes a compile-time gate impossible to build here. An earlier
/// version of this file asserted that compile error in prose while `entries`
/// was a hand-written list that would have silently omitted a new domain.
struct SetupHomePreview {
    struct Entry: Identifiable, Equatable {
        /// The directory name as it will appear in Finder, with its trailing
        /// slash — this is a folder listing, not a menu of features.
        let name: String
        /// One line, in the user's terms, of what goes in it.
        let detail: String
        let icon: String
        /// Reading order, not alphabetical order — which would open on `Apps/`,
        /// the least meaningful of them.
        let order: Int

        var id: String { name }
    }

    /// How one shared domain is described to the user, or `nil` when it is
    /// deliberately not a row of its own.
    ///
    /// Exhaustive and `default`-free on purpose: this is the compile-time gate.
    /// The four `nil` cases are not omissions — `Sage/memory`,
    /// `/skills`, `/commands` and `/sessions` are all INSIDE `Sage/`, and
    /// the listing shows top-level folders. `.agents`' copy names them.
    private static func description(of domain: SharedDomain)
        -> (detail: String, icon: String, order: Int)?
    {
        switch domain {
        case .agents:
            return (
                "Your assistant: its agents, its memory, your skills and "
                    + "commands, and every conversation it has had.",
                "bubble.left.and.text.bubble.right", 0
            )
        case .config:
            return (
                "Your settings, as plain JSON you can read.",
                "slider.horizontal.3", 1
            )
        case .media:
            return ("Images and files you bring into a conversation.", "photo", 3)
        case .sounds:
            return ("The sounds Ainkrad plays, and any you add.", "speaker.wave.2", 4)
        case .memory, .skills, .commands, .sessions:
            return nil
        // Required: `SharedDomain` is non-frozen across the module boundary, so
        // the compiler will not accept a `default`-free switch here however
        // exhaustive it is. This is exactly why the gate on a new domain is a
        // TEST — `everySharedDomainIsAccountedForInTheFolderPreview` — and not
        // this switch. The comment that used to sit here claimed a compile
        // error that the language cannot produce.
        @unknown default:
            return nil
        }
    }

    /// The top-level entries, in reading order.
    static let entries: [Entry] = {
        var rows = SharedDomain.allCases.compactMap { domain -> Entry? in
            guard let description = description(of: domain) else { return nil }
            return Entry(
                name: folderName(for: domain),
                detail: description.detail,
                icon: description.icon,
                order: description.order)
        }
        // `Apps/` has no `SharedDomain`; it is `Home.vault(app:)`'s root, so it
        // is named through that accessor rather than as a literal.
        rows.append(
            Entry(
                name: appsFolderName(),
                detail: "Whatever the apps you install make — one folder each.",
                icon: "square.grid.2x2",
                order: 2))
        return rows.sorted { $0.order < $1.order }
    }()

    /// A `Home` rooted somewhere that cannot collide with a real path. Only its
    /// URL arithmetic is used; nothing touches the file system.
    private static let probeRoot = URL(
        fileURLWithPath: "/__ainkrad-home-probe",
        isDirectory: true)
    private static var probe: Home { Home(vaultRoot: probeRoot, cacheRoot: probeRoot) }

    private static func firstComponent(of url: URL) -> String {
        url.pathComponents.dropFirst(probeRoot.pathComponents.count).first ?? "?"
    }

    private static func appsFolderName() -> String {
        firstComponent(of: probe.vault(app: AppID("probe"))) + "/"
    }

    /// The first path component of a domain's location under the vault root, as
    /// a folder name. `.memory` and friends live INSIDE `Sage/`, so the top
    /// level of this listing is the set of first components, not the set of
    /// domains.
    ///
    /// Asked of a `Home` rooted at a probe path rather than read off
    /// `SharedDomain.relativePath`, which is internal to `AinkradAppKitHome`.
    /// `shared(_:)` is the public accessor and is the same expression the app
    /// uses to build the real directories, so this stays honest either way.
    private static func folderName(for domain: SharedDomain) -> String {
        firstComponent(of: probe.shared(domain)) + "/"
    }
}

/// The warning shown on the Home step when adopting will move an existing
/// legacy container.
///
/// Derived from `VaultMigration.needsMigration(container:)`, asked BEFORE the
/// user chooses — deliberately the same predicate `LaunchHomeResolver.adopt`
/// gates the real migration on, so the warning cannot promise a move that will
/// not happen or stay silent about one that will.
///
/// This is not the same value as `HomeAdoption.Result.migrated`, and must never
/// be rebuilt from it. That flag is sampled during adoption and only exists
/// afterwards; a warning derived from it could only ever be shown once the
/// rename had already happened, which is exactly the bug this replaces. The
/// closing step keeps using it, because there the migration genuinely is in the
/// past tense.
struct SetupHomeMigrationNotice: Equatable {
    /// Where the untouched original will still be afterwards, written the way a
    /// user could paste it into Finder's Go-to-Folder.
    ///
    /// Tilde-abbreviated, matching `SetupDoneStepView.legacyCopyPath` exactly.
    /// One wizard must not name one location two ways: this screen says where
    /// the old copy WILL be and the closing screen says where it IS, and a user
    /// comparing the two should see the same string, not an absolute path in
    /// one place and `~/…` in the other.
    let legacyCopyPath: String

    /// `nil` when there is nothing to move — the overwhelmingly common case,
    /// and the reason this screen does not mention migration at all by default.
    ///
    /// Both dependencies are injected so a test can drive the decision without
    /// touching the real Application Support container; the defaults are the
    /// real ones, so the view supplies nothing.
    static func make(
        legacyContainer: URL? = VaultMigration.legacyContainerURL(),
        needsMigration: (URL) -> Bool = { VaultMigration.needsMigration(container: $0) }
    ) -> SetupHomeMigrationNotice? {
        guard let legacyContainer, needsMigration(legacyContainer) else { return nil }
        return SetupHomeMigrationNotice(
            legacyCopyPath: abbreviatingHome(
                legacyContainer
                    .appendingPathComponent("Documents.migrated", isDirectory: true)
                    .path))
    }

    /// `/Users/you/Library/…` → `~/Library/…`, so this screen names the legacy
    /// copy in the same notation `SetupDoneStepView` does.
    ///
    /// A prefix match rather than `NSString.abbreviatingWithTildeInPath`, whose
    /// exact behaviour on a path outside the user's home is not what a caller
    /// would guess. Here anything not under the home directory is returned
    /// untouched, which is both the safe answer and what an injected temporary
    /// container in a test gets.
    static func abbreviatingHome(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard !home.isEmpty, path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    var title: String { "Your existing data will be moved in" }

    var message: String {
        "Ainkrad found data from an earlier version on this Mac — your agents, "
            + "settings, skills and past conversations. When you choose a folder, "
            + "all of it is copied in first, so you carry on where you left off.\n\n"
            + "The original is not deleted. It stays where it is and is renamed to "
            + "\(legacyCopyPath), so you can check everything came across before "
            + "you remove it."
    }
}
