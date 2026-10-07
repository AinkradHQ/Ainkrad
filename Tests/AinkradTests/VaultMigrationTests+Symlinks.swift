import AinkradAppKit
import Foundation
import Testing

@testable import Ainkrad

// MARK: - Regression: a dangling symlink must never cost the user data

extension VaultMigrationTests {
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
}
