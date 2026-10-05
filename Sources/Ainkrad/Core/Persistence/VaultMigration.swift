import AinkradAppKit
import Foundation

/// Moves pre-Home data into a vault using **copy → verify → mark**.
///
/// Never moves and never deletes user data: if anything fails part-way — including
/// a full disk mid-copy — the user's files are still exactly where they have always
/// been, and the caller has not yet written a pointer, so the next launch is a clean
/// first run. The only rename this performs is the final marker (`Documents` →
/// `Documents.migrated`, inside the legacy container), and it is not part of
/// `migrate` at all: it is a separate `markMigrated` call the launch path makes
/// only after the pointer is durably written. See `markMigrated`'s doc comment
/// for why — the rename→pointer window is where a whole dataset can be stranded.
///
/// Secrets are not part of the legacy tree — they live in the Keychain and are
/// deliberately untouched here. Nothing in this type logs a file's contents.
///
/// This is the ONLY file in `Sources/` permitted to call `applicationSupportDirectory`:
/// locating the pre-Home tree is precisely its job.
enum VaultMigration {

    // MARK: - Report

    /// What happened to one row of the relocation table. Every row is always
    /// present in the report, including rows whose legacy source did not exist,
    /// so a caller can never mistake "absent" for "done".
    struct RowResult: Equatable {
        /// The row's legacy label, e.g. `"*.json"`, `"Plugins/"`, `"../Skills/"`.
        let row: String
        /// Absolute path of the destination the row maps to.
        let destination: String
        /// Whether the legacy source existed at all.
        let present: Bool
        /// Container-relative paths copied and byte-verified.
        let copied: [String]
        /// Container-relative paths left alone because the destination already existed.
        let skipped: [String]
    }

    struct Report: Equatable {
        /// Every path copied, across all rows. For the `*.json` row the entries are
        /// bare file names (`"agents.json"`); for directory rows they are prefixed
        /// with the legacy directory (`"PluginData/Lore/state.json"`).
        let copied: [String]
        /// Every path skipped because a destination file already existed.
        let skipped: [String]
        /// Row-by-row detail; one entry per relocation, in table order.
        let rows: [RowResult]

        /// True when at least one legacy source existed, i.e. there was something
        /// to migrate. Drives whether `markMigrated` has anything to mark.
        var legacyDataWasPresent: Bool { rows.contains(where: \.present) }
    }

    // MARK: - Locating the legacy tree

    /// `~/Library/Application Support/<bundle-id>`, the pre-Home container.
    static func legacyContainerURL() -> URL? {
        #if DEBUG
        // A fixture launch must never read, migrate or rename the real legacy tree.
        if debugFixtureRoots != nil { return nil }
        #endif
        guard
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ainkrad.app"
        return base.appendingPathComponent(bundleID, isDirectory: true)
    }

    /// `~/Library/Application Support/<bundle-id>/Documents`, the pre-Home document root.
    static func legacyDocumentsURL() -> URL? {
        legacyContainerURL()?.appendingPathComponent("Documents", isDirectory: true)
    }

    /// True when the container holds pre-Home data that has not been marked yet.
    static func needsMigration(container: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: container.path) else { return false }
        // Already migrated: the Documents rename is the marker.
        if entryExists(at: markerURL(container: container)) { return false }
        return rows(container: container, home: Home(vaultRoot: container, cacheRoot: container))
            .contains { row in
                switch row.kind {
                case .jsonFiles(let claimed):
                    let names = (try? fm.contentsOfDirectory(atPath: row.source.path)) ?? []
                    return names.contains { selectsJSON($0, claimed: claimed) }
                case .recursiveDirectory:
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: row.source.path, isDirectory: &isDir),
                        isDir.boolValue
                    else { return false }
                    return !(((try? fm.contentsOfDirectory(atPath: row.source.path)) ?? []).isEmpty)
                }
            }
    }

    // MARK: - The relocation table

    private enum RowKind {
        /// Top-level `*.json` documents only, non-recursive. `names` names the
        /// exact documents this row claims; `nil` means "every remaining `.json`",
        /// i.e. everything no named row above already claimed.
        case jsonFiles(names: Set<String>?)
        case recursiveDirectory
    }

    /// The legacy JSON documents that do NOT belong in `Config/`.
    ///
    /// These MUST stay in step with where the running app reads them from:
    /// `agents.json`/`connections.json` are read by the store rooted at
    /// `home.shared(.agents)`, and `assistant-sessions.json` by the store rooted
    /// at `home.shared(.sessions)` (`AppEnvironment+BootstrapStores` /
    /// `+BootstrapTools` / `+BootstrapSession`). A mismatch here does not fail —
    /// it just makes an existing user's agents, connections or chat history
    /// silently invisible — so `VaultLayoutAgreementTests` asserts the two agree.
    static let assistantJSONNames: Set<String> = ["agents.json", "connections.json"]
    static let sessionJSONNames: Set<String> = ["assistant-sessions.json"]
    private static var relocatedJSONNames: Set<String> {
        assistantJSONNames.union(sessionJSONNames)
    }

    private struct Row {
        let label: String
        /// Prefix used for the container-relative names reported for this row.
        let reportPrefix: String
        let source: URL
        let destination: URL
        let kind: RowKind
    }

    /// The relocation table, in table order. Sources are resolved against the
    /// legacy `<bundle-id>` container: the first eight live under its
    /// `Documents/`, the last four are siblings of `Documents/`.
    ///
    /// The three `.json` rows are ordered named-first, catch-all-last, and the
    /// catch-all excludes the named documents — so every top-level JSON file
    /// lands in exactly one destination.
    private static func rows(container: URL, home: Home) -> [Row] {
        let documents = container.appendingPathComponent("Documents", isDirectory: true)
        func doc(_ name: String) -> URL { documents.appendingPathComponent(name, isDirectory: true) }
        func sib(_ name: String) -> URL { container.appendingPathComponent(name, isDirectory: true) }
        let apps = home.vaultRoot.appendingPathComponent("Apps", isDirectory: true)

        return [
            // The assistant's own documents go to `Sage/`, not `Config/` —
            // the published vault layout, and where the app now reads them.
            Row(
                label: "agents.json+connections.json", reportPrefix: "",
                source: documents, destination: home.shared(.agents),
                kind: .jsonFiles(names: assistantJSONNames)),
            Row(
                label: "assistant-sessions.json", reportPrefix: "",
                source: documents, destination: home.shared(.sessions),
                kind: .jsonFiles(names: sessionJSONNames)),
            Row(
                label: "*.json", reportPrefix: "",
                source: documents, destination: home.shared(.config),
                kind: .jsonFiles(names: nil)),
            Row(
                label: "Plugins/", reportPrefix: "Plugins",
                source: doc("Plugins"),
                destination: home.cacheRoot.appendingPathComponent("Plugins", isDirectory: true),
                kind: .recursiveDirectory),
            Row(
                label: "DevPlugins/", reportPrefix: "DevPlugins",
                source: doc("DevPlugins"),
                destination: home.cacheRoot.appendingPathComponent("DevPlugins", isDirectory: true),
                kind: .recursiveDirectory),
            Row(
                label: "PluginData/", reportPrefix: "PluginData",
                source: doc("PluginData"), destination: apps, kind: .recursiveDirectory),
            Row(
                label: "RetainedPluginData/", reportPrefix: "RetainedPluginData",
                source: doc("RetainedPluginData"),
                destination: apps.appendingPathComponent(".retained", isDirectory: true),
                kind: .recursiveDirectory),
            Row(
                label: "Sounds/", reportPrefix: "Sounds",
                source: doc("Sounds"), destination: home.shared(.sounds), kind: .recursiveDirectory),
            Row(
                label: "../Skills/", reportPrefix: "Skills",
                source: sib("Skills"), destination: home.shared(.skills), kind: .recursiveDirectory),
            Row(
                label: "../Memory/", reportPrefix: "Memory",
                source: sib("Memory"), destination: home.shared(.memory), kind: .recursiveDirectory),
            Row(
                label: "../Commands/", reportPrefix: "Commands",
                source: sib("Commands"), destination: home.shared(.commands),
                kind: .recursiveDirectory),
            Row(
                label: "../Shares/", reportPrefix: "Shares",
                source: sib("Shares"),
                destination: home.shared(.sessions)
                    .appendingPathComponent("shares", isDirectory: true),
                kind: .recursiveDirectory),
        ]
    }

    private static func markerURL(container: URL) -> URL {
        container.appendingPathComponent("Documents.migrated", isDirectory: true)
    }

    // MARK: - Migrate

    /// Copies every relocated path out of the legacy `<bundle-id>` container into
    /// `home`, verifies each copy byte-for-byte, then marks the legacy `Documents`
    /// directory as migrated.
    ///
    /// - Parameter legacy: the legacy `<bundle-id>` container — NOT its `Documents`
    ///   subdirectory, because four of the ten relocated paths are siblings of it.
    /// - Throws: on the first unverifiable or failed copy, leaving no marker.
    @discardableResult
    static func migrate(fromContainer legacy: URL, into home: Home) throws -> Report {
        let fm = FileManager.default
        var results: [RowResult] = []

        for row in rows(container: legacy, home: home) {
            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: row.source.path, isDirectory: &isDir) && isDir.boolValue
            guard exists else {
                results.append(
                    RowResult(
                        row: row.label, destination: row.destination.path,
                        present: false, copied: [], skipped: []))
                continue
            }

            let (copied, skipped): ([String], [String])
            switch row.kind {
            case .jsonFiles(let claimed):
                (copied, skipped) = try migrateJSONFiles(
                    from: row.source, to: row.destination, claimed: claimed)
            case .recursiveDirectory:
                (copied, skipped) = try migrateDirectory(
                    from: row.source, to: row.destination, prefix: row.reportPrefix)
            }
            // "Present" means the legacy source existed — even if every file in it
            // was skipped. Absent and skipped must stay distinguishable.
            // `Report.legacyDataWasPresent` is derived from these flags.
            results.append(
                RowResult(
                    row: row.label, destination: row.destination.path,
                    present: true, copied: copied, skipped: skipped))
        }

        return Report(
            copied: results.flatMap(\.copied),
            skipped: results.flatMap(\.skipped),
            rows: results)
    }

    /// Renames the legacy `Documents` to `Documents.migrated` — the marker that
    /// makes `needsMigration` return false forever after.
    ///
    /// **Deliberately NOT part of `migrate`.** A verified copy is not the end of
    /// first run: the caller still has to write the pointer, and that write can
    /// fail (disk-full is exactly what a large migration provokes). If the rename
    /// happened first and the pointer write then threw, the next launch would be
    /// `.unset`, the user would pick a different folder, and this marker would
    /// make `needsMigration` answer false — adopting the new folder empty while
    /// the entire dataset sat in the first one, under a name it no longer had.
    /// Nothing would be deleted and the user would get no signal at all.
    ///
    /// So: call this LAST, only once the vault is durably claimed. Until it runs,
    /// the legacy tree keeps its original name and the next launch re-migrates.
    static func markMigrated(container legacy: URL, report: Report) throws {
        guard report.legacyDataWasPresent else { return }
        let fm = FileManager.default
        let documents = legacy.appendingPathComponent("Documents", isDirectory: true)
        let marked = markerURL(container: legacy)
        guard !entryExists(at: marked) else { return }
        if entryExists(at: documents) {
            try fm.moveItem(at: documents, to: marked)
        } else {
            // Sibling-only container (`Skills/`, `Memory/`, … and no
            // `Documents/`): a shape this routine explicitly supports, so it
            // needs the same completion signal. With nothing to rename, the
            // marker is an empty directory of the same name — `needsMigration`
            // only asks whether it exists, so a fully migrated container never
            // reports `true` again regardless of its shape.
            try fm.createDirectory(at: marked, withIntermediateDirectories: true)
        }
    }

    // MARK: - Row strategies

    /// Whether a top-level entry belongs to a `.jsonFiles` row. A named row takes
    /// exactly its own documents; the catch-all takes every other `.json`.
    private static func selectsJSON(_ name: String, claimed: Set<String>?) -> Bool {
        guard name.hasSuffix(".json") else { return false }
        if let claimed { return claimed.contains(name) }
        return !relocatedJSONNames.contains(name)
    }

    /// A `.json` row: top-level JSON documents only, non-recursive.
    private static func migrateJSONFiles(
        from source: URL, to destination: URL,
        claimed: Set<String>?
    )
        throws -> ([String], [String])
    {
        let fm = FileManager.default
        var copied: [String] = []
        var skipped: [String] = []
        let names = try fm.contentsOfDirectory(atPath: source.path).sorted()
            .filter { selectsJSON($0, claimed: claimed) }
        guard !names.isEmpty else { return ([], []) }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        for name in names {
            let target = destination.appendingPathComponent(name)
            guard !entryExists(at: target) else {
                skipped.append(name)
                continue
            }
            try copyVerified(from: source.appendingPathComponent(name), to: target)
            copied.append(name)
        }
        return (copied, skipped)
    }

    /// A directory row: recursive, file-by-file, so an existing destination file is
    /// skipped individually rather than the whole subtree being clobbered or refused.
    private static func migrateDirectory(from source: URL, to destination: URL, prefix: String)
        throws -> ([String], [String])
    {
        let fm = FileManager.default
        var copied: [String] = []
        var skipped: [String] = []

        let sourcePath = source.standardizedFileURL.path
        guard
            let walker = fm.enumerator(
                at: source,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [])
        else {
            throw CocoaError(.fileReadUnknown)
        }
        var files: [(relative: String, url: URL)] = []
        var directories: [String] = []
        for case let item as URL in walker {
            let path = item.standardizedFileURL.path
            // An entry that does not sit under the row's source cannot be given a
            // relative path, so it could be neither copied nor verified. Silently
            // dropping it inside a data migration is exactly the class of bug this
            // routine exists to avoid: refuse the row instead.
            guard path.hasPrefix(sourcePath + "/") else { throw CocoaError(.fileReadUnknown) }
            let relative = String(path.dropFirst(sourcePath.count + 1))
            var isDir: ObjCBool = false
            _ = fm.fileExists(atPath: path, isDirectory: &isDir)
            // A symlink resolving to a directory is still copied as a link, not walked.
            let isSymlink =
                (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]))?
                .isSymbolicLink ?? false
            if isDir.boolValue && !isSymlink {
                directories.append(relative)
            } else {
                files.append((relative, item))
            }
        }

        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        for relative in directories.sorted() {
            try fm.createDirectory(
                at: destination.appendingPathComponent(relative, isDirectory: true),
                withIntermediateDirectories: true)
        }

        for file in files.sorted(by: { $0.relative < $1.relative }) {
            let target = destination.appendingPathComponent(file.relative)
            let name = prefix.isEmpty ? file.relative : "\(prefix)/\(file.relative)"
            guard !entryExists(at: target) else {
                skipped.append(name)
                continue
            }
            try copyVerified(from: file.url, to: target)
            copied.append(name)
        }

        // Directory-level verification: every source entry must now exist at the
        // destination — copied by us, or already there and deliberately skipped.
        //
        // NOTE the asymmetry, deliberately: entries WE copied were byte-verified in
        // `copyVerified`; entries we SKIPPED carry no integrity guarantee at all. A
        // pre-existing destination file may be truncated or zero-byte and still
        // satisfy this sweep. That is the price of never overwriting what the user
        // already has, and the skip is reported so a caller can act on it.
        for relative in directories
        where !entryExists(
            at: destination.appendingPathComponent(relative, isDirectory: true))
        {
            throw CocoaError(.fileWriteUnknown)
        }
        for file in files
        where !entryExists(
            at: destination.appendingPathComponent(file.relative))
        {
            throw CocoaError(.fileWriteUnknown)
        }
        return (copied, skipped)
    }

    // MARK: - Copy → verify

    /// Copies one file and verifies what landed against what was read. A short
    /// write — a full disk part-way through — is silent data loss otherwise, so a
    /// failed verification removes the partial destination and throws. The SOURCE
    /// is never touched.
    ///
    /// `verify` is injectable so a test can exercise the failure branch without
    /// filling a disk.
    static func copyVerified(
        from source: URL, to target: URL,
        verify: (URL, URL) throws -> Bool = contentsMatch
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true)

        // Everything lands on a scratch path THIS call created, in the target's own
        // directory (same volume). Cleanup can then only ever remove our own scratch
        // file — never a pre-existing vault entry — which is true by construction and
        // does not depend on an earlier "does the target exist?" observation that a
        // dangling symlink or a concurrent writer could invalidate.
        let scratch = target.deletingLastPathComponent()
            .appendingPathComponent(".ainkrad-migrate-\(UUID().uuidString)")
        func discardScratch() { try? fm.removeItem(at: scratch) }

        do {
            try fm.copyItem(at: source, to: scratch)
        } catch {
            discardScratch()
            throw error
        }

        // Symlinks are copied as links; comparing the link targets, not the
        // (possibly absent) files they point at, is the only meaningful check.
        let isSymlink =
            (try? source.resourceValues(forKeys: [.isSymbolicLinkKey]))?
            .isSymbolicLink ?? false
        if isSymlink {
            let a = try? fm.destinationOfSymbolicLink(atPath: source.path)
            let b = try? fm.destinationOfSymbolicLink(atPath: scratch.path)
            guard a != nil, a == b else {
                discardScratch()
                throw CocoaError(.fileWriteUnknown)
            }
        } else {
            let matched: Bool
            do {
                matched = try verify(source, scratch)
            } catch {
                discardScratch()
                throw error
            }
            guard matched else {
                discardScratch()
                throw CocoaError(.fileWriteUnknown)
            }
        }

        // `linkItem` is `link(2)`: it fails with EEXIST if ANYTHING is at `target`
        // — including a dangling symlink, which `fileExists` reports as absent — and
        // it never follows or replaces it. That makes "publish only into an empty
        // slot" atomic rather than a check followed by a hopeful write.
        do {
            try fm.linkItem(at: scratch, to: target)
        } catch {
            discardScratch()
            throw error
        }
        discardScratch()
    }

    /// Existence that does not lie about symlinks: `FileManager.fileExists` follows
    /// links and so reports a DANGLING symlink as absent. `attributesOfItem` is
    /// `lstat`-shaped — it sees the link itself. Every "is this destination slot
    /// occupied?" decision in this file must use this, because treating a dangling
    /// symlink as an empty slot is how a migration ends up destroying a vault entry
    /// it did not create.
    static func entryExists(at url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    /// Byte-for-byte comparison, streamed in chunks so a large plugin bundle is
    /// never held in memory twice.
    static func contentsMatch(_ a: URL, _ b: URL) throws -> Bool {
        let fm = FileManager.default
        let sizeA = (try fm.attributesOfItem(atPath: a.path)[.size] as? NSNumber)?.intValue
        let sizeB = (try fm.attributesOfItem(atPath: b.path)[.size] as? NSNumber)?.intValue
        guard sizeA == sizeB else { return false }

        let handleA = try FileHandle(forReadingFrom: a)
        defer { try? handleA.close() }
        let handleB = try FileHandle(forReadingFrom: b)
        defer { try? handleB.close() }

        let chunk = 1 << 20
        while true {
            let dataA = try handleA.read(upToCount: chunk) ?? Data()
            let dataB = try handleB.read(upToCount: chunk) ?? Data()
            guard dataA == dataB else { return false }
            if dataA.isEmpty { return true }
        }
    }
}
