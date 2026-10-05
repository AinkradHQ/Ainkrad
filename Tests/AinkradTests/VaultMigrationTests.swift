import AinkradAppKit
import Foundation
import Testing

@testable import Ainkrad

@Suite("Vault migration")
struct VaultMigrationTests {
    private let fm = FileManager.default

    /// A legacy `<bundle-id>` container holding only `Documents/*.json` —
    /// the minimum shape the brief's original tests assumed.
    private func legacyContainer() throws -> URL {
        let container = fm.temporaryDirectory
            .appendingPathComponent("legacy-\(UUID().uuidString)", isDirectory: true)
        let documents = container.appendingPathComponent("Documents", isDirectory: true)
        try fm.createDirectory(at: documents, withIntermediateDirectories: true)
        try #"{"payload":{"theme":"dark"}}"#
            .write(
                to: documents.appendingPathComponent("global-settings.json"),
                atomically: true, encoding: .utf8)
        try #"{"payload":{"custom":[]}}"#
            .write(
                to: documents.appendingPathComponent("agents.json"),
                atomically: true, encoding: .utf8)
        return container
    }

    private func write(_ text: String, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func marker(_ container: URL) -> URL {
        container.appendingPathComponent("Documents.migrated", isDirectory: true)
    }

    private func outcome(_ report: VaultMigration.Report, _ row: String) -> VaultMigration.RowResult? {
        report.rows.first { $0.row == row }
    }

    // MARK: - The `*.json` row

    @Test func documentsAreCopiedIntoTheVaultConfigDirectory() throws {
        let legacy = try legacyContainer()
        defer { try? fm.removeItem(at: legacy) }
        let t = TestHome.make("mig")
        defer { t.cleanup() }

        let report = try VaultMigration.migrate(fromContainer: legacy, into: t.home)

        #expect(report.copied.sorted() == ["agents.json", "global-settings.json"])
        #expect(report.skipped.isEmpty)
        #expect(
            fm.fileExists(
                atPath: t.home.shared(.config).appendingPathComponent("global-settings.json").path))
        // `agents.json` is an Sage/ document, NOT a Config/ one.
        #expect(
            !fm.fileExists(
                atPath: t.home.shared(.config).appendingPathComponent("agents.json").path))
        #expect(
            try String(
                contentsOf: t.home.shared(.agents)
                    .appendingPathComponent("agents.json"), encoding: .utf8) == #"{"payload":{"custom":[]}}"#)
    }

    @Test func theLegacyTreeIsPreservedNotDeleted() throws {
        let legacy = try legacyContainer()
        defer { try? fm.removeItem(at: legacy) }
        let t = TestHome.make("mig2")
        defer { t.cleanup() }

        let report = try VaultMigration.migrate(fromContainer: legacy, into: t.home)
        // Marking is a SEPARATE step the launch path takes only after the pointer
        // is written — see `markMigrated`. `migrate` alone never renames.
        #expect(
            !fm.fileExists(atPath: marker(legacy).path),
            "migrate must not rename; only markMigrated does")
        try VaultMigration.markMigrated(container: legacy, report: report)

        let marked = marker(legacy)
        #expect(fm.fileExists(atPath: marked.path), "migration must mark, never delete")
        #expect(fm.fileExists(atPath: marked.appendingPathComponent("global-settings.json").path))
        #expect(
            !fm.fileExists(atPath: legacy.appendingPathComponent("Documents").path),
            "the marker is the renamed Documents directory")
    }

    @Test func migrationIsSkippedWhenTheVaultAlreadyHasTheDocument() throws {
        let legacy = try legacyContainer()
        defer { try? fm.removeItem(at: legacy) }
        let t = TestHome.make("mig3")
        defer { t.cleanup() }

        try fm.createDirectory(at: t.home.shared(.agents), withIntermediateDirectories: true)
        try "{}".write(
            to: t.home.shared(.agents).appendingPathComponent("agents.json"),
            atomically: true, encoding: .utf8)

        let report = try VaultMigration.migrate(fromContainer: legacy, into: t.home)

        #expect(report.copied == ["global-settings.json"])
        #expect(report.skipped == ["agents.json"])
        // The pre-existing destination file is untouched.
        #expect(
            try String(
                contentsOf: t.home.shared(.agents)
                    .appendingPathComponent("agents.json"), encoding: .utf8) == "{}")
    }

    @Test func nonJSONFilesInDocumentsAreNotCopied() throws {
        let legacy = try legacyContainer()
        defer { try? fm.removeItem(at: legacy) }
        let t = TestHome.make("mig4")
        defer { t.cleanup() }

        try write("noise", to: legacy.appendingPathComponent("Documents/scratch.txt"))

        let report = try VaultMigration.migrate(fromContainer: legacy, into: t.home)

        #expect(!report.copied.contains("scratch.txt"))
        #expect(
            !fm.fileExists(
                atPath: t.home.shared(.config).appendingPathComponent("scratch.txt").path))
    }

    // MARK: - Every row is accounted for

    @Test func everyRelocationRowAppearsInTheReport() throws {
        let legacy = try legacyContainer()
        defer { try? fm.removeItem(at: legacy) }
        let t = TestHome.make("mig5")
        defer { t.cleanup() }

        let report = try VaultMigration.migrate(fromContainer: legacy, into: t.home)

        #expect(
            report.rows.map(\.row) == [
                "agents.json+connections.json", "assistant-sessions.json", "*.json",
                "Plugins/", "DevPlugins/", "PluginData/", "RetainedPluginData/",
                "Sounds/", "../Skills/", "../Memory/", "../Commands/", "../Shares/",
            ])
        // The three JSON rows all read the same `Documents/`, so all three are
        // "present"; every directory row is absent in a JSON-only container.
        let jsonRows = ["agents.json+connections.json", "assistant-sessions.json", "*.json"]
        for row in report.rows where !jsonRows.contains(row.row) {
            #expect(!row.present, "\(row.row) should be absent in a JSON-only container")
            #expect(row.copied.isEmpty)
        }
        for row in jsonRows { #expect(outcome(report, row)?.present == true) }
    }

    // MARK: - Directory rows (recursive)

    @Test func pluginDataDirectoryIsCopiedRecursively() throws {
        let legacy = try legacyContainer()
        defer { try? fm.removeItem(at: legacy) }
        let t = TestHome.make("mig6")
        defer { t.cleanup() }

        try write("a", to: legacy.appendingPathComponent("Documents/PluginData/Lore/notes/one.md"))
        try write("b", to: legacy.appendingPathComponent("Documents/PluginData/Lore/state.json"))

        let report = try VaultMigration.migrate(fromContainer: legacy, into: t.home)

        let apps = t.home.vaultRoot.appendingPathComponent("Apps", isDirectory: true)
        #expect(
            try String(
                contentsOf: apps.appendingPathComponent("Lore/notes/one.md"),
                encoding: .utf8) == "a")
        #expect(
            try String(
                contentsOf: apps.appendingPathComponent("Lore/state.json"),
                encoding: .utf8) == "b")
        #expect(
            outcome(report, "PluginData/")?.copied.sorted() == [
                "PluginData/Lore/notes/one.md", "PluginData/Lore/state.json",
            ])
        #expect(report.copied.contains("PluginData/Lore/state.json"))
    }

    @Test func pluginBinariesAreCopiedNotSkipped() throws {
        let legacy = try legacyContainer()
        defer { try? fm.removeItem(at: legacy) }
        let t = TestHome.make("mig7")
        defer { t.cleanup() }

        try write(
            "plist",
            to: legacy.appendingPathComponent(
                "Documents/Plugins/Lore.bundle/Contents/Info.plist"))
        try write(
            "dev",
            to: legacy.appendingPathComponent(
                "Documents/DevPlugins/Dev.bundle/Contents/Info.plist"))

        let report = try VaultMigration.migrate(fromContainer: legacy, into: t.home)

        #expect(
            fm.fileExists(
                atPath: t.home.cacheRoot
                    .appendingPathComponent("Plugins/Lore.bundle/Contents/Info.plist").path))
        #expect(
            fm.fileExists(
                atPath: t.home.cacheRoot
                    .appendingPathComponent("DevPlugins/Dev.bundle/Contents/Info.plist").path))
        #expect(outcome(report, "Plugins/")?.copied == ["Plugins/Lore.bundle/Contents/Info.plist"])
        #expect(outcome(report, "DevPlugins/")?.copied == ["DevPlugins/Dev.bundle/Contents/Info.plist"])
    }

    @Test func existingDestinationFilesInADirectoryRowAreSkipped() throws {
        let legacy = try legacyContainer()
        defer { try? fm.removeItem(at: legacy) }
        let t = TestHome.make("mig8")
        defer { t.cleanup() }

        try write("new", to: legacy.appendingPathComponent("Documents/Sounds/ping.wav"))
        try write("old", to: t.home.shared(.sounds).appendingPathComponent("ping.wav"))

        let report = try VaultMigration.migrate(fromContainer: legacy, into: t.home)

        #expect(outcome(report, "Sounds/")?.skipped == ["Sounds/ping.wav"])
        #expect(outcome(report, "Sounds/")?.copied.isEmpty == true)
        #expect(
            try String(
                contentsOf: t.home.shared(.sounds)
                    .appendingPathComponent("ping.wav"), encoding: .utf8) == "old")
    }

    // MARK: - Sibling rows

    @Test func siblingDirectoriesOutsideDocumentsAreMigrated() throws {
        let legacy = try legacyContainer()
        defer { try? fm.removeItem(at: legacy) }
        let t = TestHome.make("mig9")
        defer { t.cleanup() }

        try write("---\nname: pdf\n---", to: legacy.appendingPathComponent("Skills/pdf/SKILL.md"))
        try write("# memory", to: legacy.appendingPathComponent("Memory/notes.md"))
        try write("# cmd", to: legacy.appendingPathComponent("Commands/ship.md"))
        try write("<html>", to: legacy.appendingPathComponent("Shares/abc/index.html"))

        let report = try VaultMigration.migrate(fromContainer: legacy, into: t.home)

        #expect(
            fm.fileExists(
                atPath: t.home.shared(.skills)
                    .appendingPathComponent("pdf/SKILL.md").path))
        #expect(
            fm.fileExists(
                atPath: t.home.shared(.memory)
                    .appendingPathComponent("notes.md").path))
        #expect(
            fm.fileExists(
                atPath: t.home.shared(.commands)
                    .appendingPathComponent("ship.md").path))
        #expect(
            fm.fileExists(
                atPath: t.home.shared(.sessions)
                    .appendingPathComponent("shares/abc/index.html").path))
        #expect(outcome(report, "../Skills/")?.copied == ["Skills/pdf/SKILL.md"])
        #expect(outcome(report, "../Shares/")?.copied == ["Shares/abc/index.html"])
        // Siblings are copied, never renamed: the legacy tree stays put.
        #expect(fm.fileExists(atPath: legacy.appendingPathComponent("Skills/pdf/SKILL.md").path))
    }

    @Test func retainedPluginDataLandsUnderTheDotRetainedDirectory() throws {
        let legacy = try legacyContainer()
        defer { try? fm.removeItem(at: legacy) }
        let t = TestHome.make("mig10")
        defer { t.cleanup() }

        try write(
            "kept",
            to: legacy.appendingPathComponent(
                "Documents/RetainedPluginData/Lore/keep.json"))

        _ = try VaultMigration.migrate(fromContainer: legacy, into: t.home)

        #expect(
            try String(
                contentsOf: t.home.vaultRoot
                    .appendingPathComponent("Apps/.retained/Lore/keep.json"), encoding: .utf8) == "kept")
    }

    // MARK: - Safety discipline

    @Test func nothingIsDeletedFromTheLegacyTree() throws {
        let legacy = try legacyContainer()
        defer { try? fm.removeItem(at: legacy) }
        let t = TestHome.make("mig11")
        defer { t.cleanup() }

        try write("a", to: legacy.appendingPathComponent("Documents/PluginData/Lore/one.md"))
        try write("s", to: legacy.appendingPathComponent("Skills/pdf/SKILL.md"))

        let report = try VaultMigration.migrate(fromContainer: legacy, into: t.home)
        try VaultMigration.markMigrated(container: legacy, report: report)

        let marked = marker(legacy)
        #expect(fm.fileExists(atPath: marked.appendingPathComponent("PluginData/Lore/one.md").path))
        #expect(fm.fileExists(atPath: marked.appendingPathComponent("global-settings.json").path))
        #expect(fm.fileExists(atPath: legacy.appendingPathComponent("Skills/pdf/SKILL.md").path))
    }

    @Test func aFailedCopyThrowsAndLeavesNoMarker() throws {
        let legacy = try legacyContainer()
        defer { try? fm.removeItem(at: legacy) }
        let t = TestHome.make("mig12")
        defer { t.cleanup() }

        // Simulate a mid-copy failure: the destination for the `Sounds/` row is a
        // regular FILE, so creating the directory under it fails part-way through.
        try write("blocker", to: t.home.shared(.sounds))
        try write("wav", to: legacy.appendingPathComponent("Documents/Sounds/ping.wav"))

        #expect(throws: (any Error).self) {
            _ = try VaultMigration.migrate(fromContainer: legacy, into: t.home)
        }

        // Legacy data is exactly where it always was, and nothing was marked —
        // so the next launch is a clean first run.
        #expect(!fm.fileExists(atPath: marker(legacy).path))
        #expect(fm.fileExists(atPath: legacy.appendingPathComponent("Documents/Sounds/ping.wav").path))
        #expect(
            fm.fileExists(
                atPath: legacy.appendingPathComponent("Documents/global-settings.json").path))
    }

    @Test func aCorruptedCopyIsDetectedAndRemoved() throws {
        let legacy = try legacyContainer()
        defer { try? fm.removeItem(at: legacy) }
        let t = TestHome.make("mig13")
        defer { t.cleanup() }

        let source = legacy.appendingPathComponent("Documents/PluginData/Lore/one.md")
        try write("original", to: source)

        #expect(throws: (any Error).self) {
            try VaultMigration.copyVerified(
                from: source,
                to: t.home.vaultRoot.appendingPathComponent("Apps/Lore/one.md"),
                verify: { _, _ in false })
        }
        #expect(
            !fm.fileExists(
                atPath: t.home.vaultRoot.appendingPathComponent("Apps/Lore/one.md").path))
        #expect(fm.fileExists(atPath: source.path), "the source is never touched")
    }

    @Test func verificationComparesContentNotJustExistence() throws {
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: base) }
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        let a = base.appendingPathComponent("a")
        let b = base.appendingPathComponent("b")
        let c = base.appendingPathComponent("c")
        try write(String(repeating: "x", count: 200_000), to: a)
        try write(String(repeating: "x", count: 200_000), to: b)
        try write(String(repeating: "x", count: 199_999) + "y", to: c)

        #expect(try VaultMigration.contentsMatch(a, b))
        #expect(try VaultMigration.contentsMatch(a, c) == false)
    }

    // MARK: - needsMigration / discovery

    @Test func needsMigrationIsFalseOnceMarked() throws {
        let legacy = try legacyContainer()
        defer { try? fm.removeItem(at: legacy) }
        let t = TestHome.make("mig14")
        defer { t.cleanup() }

        #expect(VaultMigration.needsMigration(container: legacy))
        let report = try VaultMigration.migrate(fromContainer: legacy, into: t.home)
        // A verified copy alone does NOT stop the container needing migration:
        // until the pointer exists, a re-run must still be able to happen.
        #expect(VaultMigration.needsMigration(container: legacy))
        try VaultMigration.markMigrated(container: legacy, report: report)
        #expect(!VaultMigration.needsMigration(container: legacy))
    }

    @Test func needsMigrationIsTrueForSiblingOnlyContainers() throws {
        let container = fm.temporaryDirectory
            .appendingPathComponent("legacy-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: container) }
        try write("s", to: container.appendingPathComponent("Skills/pdf/SKILL.md"))

        #expect(VaultMigration.needsMigration(container: container))
    }

    /// A container with no `Documents/` still has to record completion, or Task 8
    /// re-runs a full byte-verifying migration on every launch.
    @Test func aSiblingOnlyContainerIsMarkedAndStopsNeedingMigration() throws {
        let container = fm.temporaryDirectory
            .appendingPathComponent("legacy-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: container) }
        try write("s", to: container.appendingPathComponent("Skills/pdf/SKILL.md"))
        try write("m", to: container.appendingPathComponent("Memory/notes.md"))
        let t = TestHome.make("mig16")
        defer { t.cleanup() }

        let report = try VaultMigration.migrate(fromContainer: container, into: t.home)

        #expect(report.copied.sorted() == ["Memory/notes.md", "Skills/pdf/SKILL.md"])
        try VaultMigration.markMigrated(container: container, report: report)
        #expect(fm.fileExists(atPath: marker(container).path), "completion must be recorded")
        #expect(!VaultMigration.needsMigration(container: container))
        // Siblings are copies: the legacy files are still exactly where they were.
        #expect(fm.fileExists(atPath: container.appendingPathComponent("Skills/pdf/SKILL.md").path))
    }

    // MARK: - Regression: a dangling symlink must never cost the user data

    @Test func aDanglingSymlinkAtTheDestinationIsSkippedAndSurvives() throws {
        let legacy = try legacyContainer()
        defer { try? fm.removeItem(at: legacy) }
        let t = TestHome.make("mig17")
        defer { t.cleanup() }

        // `FileManager.fileExists` reports a dangling symlink as ABSENT. If the skip
        // guard believed it, `copyItem` would fail with "file exists" and the old
        // cleanup path would then delete this pre-existing vault entry — destroying
        // something the migration never created.
        let assistant = t.home.shared(.agents)
        try fm.createDirectory(at: assistant, withIntermediateDirectories: true)
        let link = assistant.appendingPathComponent("agents.json")
        try fm.createSymbolicLink(
            at: link,
            withDestinationURL:
                assistant.appendingPathComponent("nowhere-\(UUID().uuidString).json"))
        #expect(!fm.fileExists(atPath: link.path), "precondition: fileExists lies here")

        let report = try VaultMigration.migrate(fromContainer: legacy, into: t.home)

        #expect(report.skipped == ["agents.json"])
        #expect(report.copied == ["global-settings.json"])
        let attributes = try fm.attributesOfItem(atPath: link.path)
        #expect(
            attributes[.type] as? FileAttributeType == .typeSymbolicLink,
            "the user's entry must still be there, untouched")
    }

    @Test func aDanglingSymlinkInsideADirectoryRowIsSkippedAndSurvives() throws {
        let legacy = try legacyContainer()
        defer { try? fm.removeItem(at: legacy) }
        let t = TestHome.make("mig18")
        defer { t.cleanup() }

        try write("new", to: legacy.appendingPathComponent("Documents/Sounds/ping.wav"))
        let sounds = t.home.shared(.sounds)
        try fm.createDirectory(at: sounds, withIntermediateDirectories: true)
        let link = sounds.appendingPathComponent("ping.wav")
        try fm.createSymbolicLink(
            at: link,
            withDestinationURL:
                sounds.appendingPathComponent("gone-\(UUID().uuidString).wav"))

        let report = try VaultMigration.migrate(fromContainer: legacy, into: t.home)

        #expect(outcome(report, "Sounds/")?.skipped == ["Sounds/ping.wav"])
        #expect(
            try fm.attributesOfItem(atPath: link.path)[.type] as? FileAttributeType
                == .typeSymbolicLink)
    }

    @Test func aFailedPublishNeverRemovesAPreExistingDestinationEntry() throws {
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: base) }
        let source = base.appendingPathComponent("src.txt")
        try write("payload", to: source)
        let target = base.appendingPathComponent("dst.txt")
        try write("precious", to: target)

        // Publishing into an occupied slot must fail rather than overwrite, and the
        // failure must not take the occupant with it.
        #expect(throws: (any Error).self) {
            try VaultMigration.copyVerified(from: source, to: target)
        }
        #expect(try String(contentsOf: target, encoding: .utf8) == "precious")
        // And no scratch file is left behind.
        let leftovers = try fm.contentsOfDirectory(atPath: base.path)
            .filter { $0.hasPrefix(".ainkrad-migrate-") }
        #expect(leftovers.isEmpty)
    }

    @Test func entryExistsSeesWhatFileExistsCannot() throws {
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        let link = base.appendingPathComponent("dangling")
        try fm.createSymbolicLink(at: link, withDestinationURL: base.appendingPathComponent("nope"))

        #expect(!fm.fileExists(atPath: link.path))
        #expect(VaultMigration.entryExists(at: link))
        #expect(!VaultMigration.entryExists(at: base.appendingPathComponent("truly-absent")))
    }

    @Test func needsMigrationIsFalseForAnEmptyOrMissingContainer() throws {
        let container = fm.temporaryDirectory
            .appendingPathComponent("legacy-\(UUID().uuidString)", isDirectory: true)
        #expect(!VaultMigration.needsMigration(container: container))
        try fm.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: container) }
        #expect(!VaultMigration.needsMigration(container: container))
    }

    @Test func migratingAnEmptyContainerIsANoOpWithoutAMarker() throws {
        let container = fm.temporaryDirectory
            .appendingPathComponent("legacy-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: container) }
        let t = TestHome.make("mig15")
        defer { t.cleanup() }

        let report = try VaultMigration.migrate(fromContainer: container, into: t.home)

        #expect(report.copied.isEmpty)
        #expect(report.rows.allSatisfy { !$0.present })
        #expect(!fm.fileExists(atPath: marker(container).path))
    }

    @Test func legacyContainerURLIsTheBundleIdentifierDirectory() throws {
        let container = try #require(VaultMigration.legacyContainerURL())
        #expect(container.lastPathComponent == (Bundle.main.bundleIdentifier ?? "com.ainkrad.app"))
        #expect(VaultMigration.legacyDocumentsURL()?.lastPathComponent == "Documents")
        #expect(
            VaultMigration.legacyDocumentsURL()?.deletingLastPathComponent().path
                == container.path)
    }
}
