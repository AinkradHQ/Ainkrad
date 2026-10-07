import AinkradAppKit
import Foundation
import Testing

@testable import Ainkrad

@Suite("Home adoption")
@MainActor
struct HomeAdoptionTests {
    private func sandbox(_ label: String) -> (base: URL, pointer: URL, cache: URL, vault: URL) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        return (
            base,
            base.appendingPathComponent("pointer"),
            base.appendingPathComponent("cache"),
            base.appendingPathComponent("vault")
        )
    }

    @Test func adoptingRebuildsTheEnvironmentAgainstTheChosenVault() throws {
        let s = sandbox("adopt")
        defer { try? FileManager.default.removeItem(at: s.base) }
        try FileManager.default.createDirectory(at: s.vault, withIntermediateDirectories: true)

        let suite = "com.ainkrad.tests.adopt.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var installed: AppEnvironment?
        let result = try HomeAdoption.adoptAndRebuild(
            chosen: s.vault,
            pointerDirectory: s.pointer,
            cacheRoot: s.cache,
            legacyContainer: nil,
            defaults: defaults,
            install: { installed = $0 })

        #expect(result.home.vaultRoot.standardizedFileURL == s.vault.standardizedFileURL)
        #expect(installed != nil)
        // The rebuilt environment must persist into the chosen vault, not anywhere else.
        installed?.themeManager.setFontScale(.large)
        #expect(
            FileManager.default.fileExists(
                atPath: s.vault.appendingPathComponent("Config/global-settings.json").path))
    }

    @Test func aFailedAdoptionInstallsNothing() throws {
        let s = sandbox("adopt-fail")
        defer { try? FileManager.default.removeItem(at: s.base) }
        try FileManager.default.createDirectory(at: s.vault, withIntermediateDirectories: true)
        // Populated and not a home -> HomeError.notEmpty
        try "x".write(
            to: s.vault.appendingPathComponent("occupied.txt"),
            atomically: true, encoding: .utf8)

        let suite = "com.ainkrad.tests.adoptfail.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var installed: AppEnvironment?
        #expect(throws: (any Error).self) {
            _ = try HomeAdoption.adoptAndRebuild(
                chosen: s.vault, pointerDirectory: s.pointer, cacheRoot: s.cache,
                legacyContainer: nil, defaults: defaults, install: { installed = $0 })
        }
        #expect(installed == nil, "a failed adoption must not install a half-built environment")
        #expect(!FileManager.default.fileExists(atPath: s.pointer.appendingPathComponent("home.json").path))
    }

    /// `Result.migrated` is what the wizard shows the user ("your existing data
    /// was moved into your new vault"), so a false claim in either direction is
    /// user-visible. Both other tests pass `legacyContainer: nil`, which never
    /// exercises it.
    @Test func migratedReportsTrueOnlyWhenALegacyContainerWasActuallyMoved() throws {
        let s = sandbox("adopt-migrate")
        defer { try? FileManager.default.removeItem(at: s.base) }
        try FileManager.default.createDirectory(at: s.vault, withIntermediateDirectories: true)

        // A sibling-only legacy container: the minimal shape `needsMigration`
        // answers true for.
        let legacy = s.base.appendingPathComponent("legacy", isDirectory: true)
        let skill = legacy.appendingPathComponent("Skills/pdf/SKILL.md")
        try FileManager.default.createDirectory(
            at: skill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# pdf".write(to: skill, atomically: true, encoding: .utf8)
        #expect(VaultMigration.needsMigration(container: legacy))

        let suite = "com.ainkrad.tests.adoptmigrate.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let result = try HomeAdoption.adoptAndRebuild(
            chosen: s.vault, pointerDirectory: s.pointer, cacheRoot: s.cache,
            legacyContainer: legacy, defaults: defaults, install: { _ in })

        #expect(result.migrated)
        // `migrated` must mean the migration HAPPENED, not merely that it was
        // wanted: the container is marked (so a relaunch won't re-run it) and
        // the skill is in the adopted vault.
        #expect(!VaultMigration.needsMigration(container: legacy))
        #expect(
            FileManager.default.fileExists(
                atPath: result.home.shared(.skills).appendingPathComponent("pdf/SKILL.md").path))
    }

    @Test func migratedIsFalseWhenTheLegacyContainerHasNothingToMove() throws {
        let s = sandbox("adopt-nomigrate")
        defer { try? FileManager.default.removeItem(at: s.base) }
        try FileManager.default.createDirectory(at: s.vault, withIntermediateDirectories: true)
        let legacy = s.base.appendingPathComponent("legacy-empty", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)

        let suite = "com.ainkrad.tests.adoptnomigrate.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let result = try HomeAdoption.adoptAndRebuild(
            chosen: s.vault, pointerDirectory: s.pointer, cacheRoot: s.cache,
            legacyContainer: legacy, defaults: defaults, install: { _ in })

        #expect(!result.migrated)
    }
}
