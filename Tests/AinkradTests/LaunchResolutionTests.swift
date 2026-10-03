import Foundation
import Testing
@testable import Ainkrad
import AinkradAppKit

@Suite("Launch resolution")
struct LaunchResolutionTests {
    private func sandbox(_ label: String) -> (base: URL, pointer: URL, cache: URL) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        return (base,
                base.appendingPathComponent("pointer"),
                base.appendingPathComponent("cache"))
    }

    @Test func firstLaunchAdoptsTheFolderTheUserChose() throws {
        let s = sandbox("launch")
        defer { try? FileManager.default.removeItem(at: s.base) }
        let chosen = s.base.appendingPathComponent("Chosen")
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)

        let home = try LaunchHomeResolver.resolveOrAdopt(
            chooseVault: { chosen }, pointerDirectory: s.pointer, cacheRoot: s.cache,
            legacyContainer: nil)

        #expect(home.vaultRoot.standardizedFileURL == chosen.standardizedFileURL)
        #expect(FileManager.default.fileExists(
            atPath: chosen.appendingPathComponent(".ainkrad-home").path))
    }

    /// Cancelling must not produce a Home. Nothing is chosen on the user's behalf,
    /// and nothing is written.
    @Test func cancellingTheChooserAdoptsNothing() throws {
        let s = sandbox("cancel")
        defer { try? FileManager.default.removeItem(at: s.base) }

        #expect(throws: LaunchHomeResolver.Failure.setupCancelled) {
            _ = try LaunchHomeResolver.resolveOrAdopt(
                chooseVault: { nil }, pointerDirectory: s.pointer, cacheRoot: s.cache, legacyContainer: nil)
        }
        guard case .unset = AinkradHome.resolve(pointerDirectory: s.pointer, cacheRoot: s.cache)
        else { Issue.record("a cancelled setup must leave no pointer"); return }
    }

    /// The folder chooser is never even shown when a Home is already configured —
    /// a launch that asks again would invite the user to create a second vault.
    @Test func aConfiguredHomeNeverPresentsTheChooser() throws {
        let s = sandbox("configured")
        defer { try? FileManager.default.removeItem(at: s.base) }
        let vault = s.base.appendingPathComponent("Vault")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        _ = try AinkradHome.adopt(vault, pointerDirectory: s.pointer, cacheRoot: s.cache)

        var chooserCalls = 0
        let home = try LaunchHomeResolver.resolveOrAdopt(
            chooseVault: { chooserCalls += 1; return nil },
            pointerDirectory: s.pointer, cacheRoot: s.cache, legacyContainer: nil)

        #expect(chooserCalls == 0)
        #expect(home.vaultRoot.standardizedFileURL == vault.standardizedFileURL)
    }

    /// The prohibited behaviour: a configured-but-unreachable vault must never
    /// silently become a fresh one somewhere else — and must not even ask.
    @Test func aMissingVaultDoesNotSilentlyBecomeANewOne() throws {
        let s = sandbox("launch2")
        defer { try? FileManager.default.removeItem(at: s.base) }
        let vault = s.base.appendingPathComponent("Vault")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        _ = try AinkradHome.adopt(vault, pointerDirectory: s.pointer, cacheRoot: s.cache)
        try FileManager.default.removeItem(at: vault)

        let elsewhere = s.base.appendingPathComponent("Elsewhere")
        #expect(throws: LaunchHomeResolver.Failure.vaultMissing(path: vault.path)) {
            _ = try LaunchHomeResolver.resolveOrAdopt(
                chooseVault: { elsewhere }, pointerDirectory: s.pointer, cacheRoot: s.cache, legacyContainer: nil)
        }
        #expect(!FileManager.default.fileExists(atPath: elsewhere.path))
    }

    /// A directory that exists but is not a home must not be re-adopted, and must
    /// not cause a fresh vault to appear elsewhere either.
    @Test func aForeignVaultThrows() throws {
        let s = sandbox("launch3")
        defer { try? FileManager.default.removeItem(at: s.base) }
        let vault = s.base.appendingPathComponent("Vault")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        _ = try AinkradHome.adopt(vault, pointerDirectory: s.pointer, cacheRoot: s.cache)
        try FileManager.default.removeItem(at: vault.appendingPathComponent(".ainkrad-home"))

        let elsewhere = s.base.appendingPathComponent("Elsewhere")
        #expect(throws: LaunchHomeResolver.Failure.notAnAinkradHome(path: vault.path)) {
            _ = try LaunchHomeResolver.resolveOrAdopt(
                chooseVault: { elsewhere }, pointerDirectory: s.pointer, cacheRoot: s.cache, legacyContainer: nil)
        }
        #expect(!FileManager.default.fileExists(atPath: elsewhere.path))
    }

    /// The incident: the user picks a folder that already holds their own files.
    /// It must be refused, and refused BEFORE anything is written into it.
    @Test func choosingAPopulatedFolderIsRefusedAndWritesNothing() throws {
        let s = sandbox("populated")
        defer { try? FileManager.default.removeItem(at: s.base) }
        let chosen = s.base.appendingPathComponent("MyNotes")
        try FileManager.default.createDirectory(
            at: chosen.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: chosen.appendingPathComponent("Note.md"))

        #expect(throws: HomeError.notEmpty(chosen)) {
            _ = try LaunchHomeResolver.resolveOrAdopt(
                chooseVault: { chosen }, pointerDirectory: s.pointer, cacheRoot: s.cache, legacyContainer: nil)
        }

        // Untouched: no marker, no pointer, no new entries.
        #expect(!FileManager.default.fileExists(
            atPath: chosen.appendingPathComponent(".ainkrad-home").path))
        let names = Set(try FileManager.default.contentsOfDirectory(atPath: chosen.path))
        #expect(names == [".obsidian", "Note.md"])
        guard case .unset = AinkradHome.resolve(pointerDirectory: s.pointer, cacheRoot: s.cache)
        else { Issue.record("a refused choice must leave no pointer"); return }
    }

    /// First-run adoption migrates the legacy container into the chosen vault.
    /// Every other test here passes `legacyContainer: nil`, so this is the one
    /// that proves the wiring is actually connected.
    @Test func firstRunMigratesTheLegacyContainer() throws {
        let s = sandbox("migrate")
        defer { try? FileManager.default.removeItem(at: s.base) }
        let chosen = s.base.appendingPathComponent("Chosen")
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)

        let legacy = s.base.appendingPathComponent("com.ainkrad.app")
        let documents = legacy.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try Data(#"{"a":1}"#.utf8).write(to: documents.appendingPathComponent("agents.json"))

        let home = try LaunchHomeResolver.resolveOrAdopt(
            chooseVault: { chosen }, pointerDirectory: s.pointer, cacheRoot: s.cache,
            legacyContainer: legacy)

        #expect(FileManager.default.fileExists(
            atPath: home.shared(.agents).appendingPathComponent("agents.json").path))
        // Copy, not move: the legacy file is still there, under the marker rename.
        #expect(FileManager.default.fileExists(
            atPath: legacy.appendingPathComponent("Documents.migrated/agents.json").path))
    }

    /// The stranding scenario, and the reason the `Documents` rename happens
    /// AFTER `adopt` rather than as migration's last step.
    ///
    /// A verified copy is not the end of first run — the pointer still has to be
    /// written, and that write can fail (disk-full is exactly what a large
    /// migration provokes). If the rename had already happened, the next launch
    /// would be `.unset`, the user would pick a different folder, `needsMigration`
    /// would answer false because the marker was there, and the new folder would
    /// be adopted EMPTY while the whole dataset sat in the first one under a name
    /// it no longer had. Nothing deleted, no signal at all.
    @Test func anAdoptFailureAfterAVerifiedCopyLeavesTheLegacyTreeReMigratable() throws {
        let s = sandbox("strand")
        defer { try? FileManager.default.removeItem(at: s.base) }
        let folderA = s.base.appendingPathComponent("A")
        try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)

        let legacy = s.base.appendingPathComponent("com.ainkrad.app")
        let documents = legacy.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try Data(#"{"payload":{"theme":"dark"}}"#.utf8)
            .write(to: documents.appendingPathComponent("global-settings.json"))

        // Make the POINTER write fail, and only the pointer write: the pointer
        // directory's parent is a regular file, so it can never be created. The
        // copy above it succeeds in full first.
        let blocker = s.base.appendingPathComponent("blocker")
        try Data("x".utf8).write(to: blocker)
        let doomedPointer = blocker.appendingPathComponent("pointer")

        #expect(throws: (any Error).self) {
            _ = try LaunchHomeResolver.resolveOrAdopt(
                chooseVault: { folderA }, pointerDirectory: doomedPointer,
                cacheRoot: s.cache, legacyContainer: legacy)
        }

        // The copy DID happen…
        #expect(FileManager.default.fileExists(
            atPath: folderA.appendingPathComponent("Config/global-settings.json").path))
        // …but the legacy tree still has its ORIGINAL name, so nothing is stranded.
        #expect(FileManager.default.fileExists(
            atPath: documents.appendingPathComponent("global-settings.json").path),
                "the rename must not have happened")
        #expect(!FileManager.default.fileExists(
            atPath: legacy.appendingPathComponent("Documents.migrated").path))
        #expect(VaultMigration.needsMigration(container: legacy),
                "the next launch must still see work to do")

        // And the retry — the user picks a DIFFERENT folder, exactly as they would
        // after a blank first launch — actually gets their data.
        let folderB = s.base.appendingPathComponent("B")
        try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)
        let home = try LaunchHomeResolver.resolveOrAdopt(
            chooseVault: { folderB }, pointerDirectory: s.pointer, cacheRoot: s.cache,
            legacyContainer: legacy)

        #expect(home.vaultRoot.standardizedFileURL == folderB.standardizedFileURL)
        #expect(FileManager.default.fileExists(
            atPath: folderB.appendingPathComponent("Config/global-settings.json").path),
                "folder B must NOT come up empty")
        // Only now, with a pointer durably written, is the legacy tree marked.
        #expect(FileManager.default.fileExists(
            atPath: legacy.appendingPathComponent("Documents.migrated/global-settings.json").path))
    }

    /// A first run that died part-way through migration leaves a marked but
    /// pointer-less folder. The retry must be able to choose that same folder —
    /// it is now non-empty, so without the marker exemption the user would be
    /// permanently locked out of the folder the app itself half-filled.
    @Test func aHalfMigratedFolderCanBeChosenAgain() throws {
        let s = sandbox("resume")
        defer { try? FileManager.default.removeItem(at: s.base) }
        let chosen = s.base.appendingPathComponent("Chosen")
        try FileManager.default.createDirectory(
            at: chosen.appendingPathComponent("Config"), withIntermediateDirectories: true)
        try Data(#"{"a":1}"#.utf8).write(to: chosen.appendingPathComponent("Config/agents.json"))
        let marker = HomeMarker()
        try marker.write(to: chosen)   // …but no pointer: the run never got that far.

        guard case .unset = AinkradHome.resolve(pointerDirectory: s.pointer, cacheRoot: s.cache)
        else { Issue.record("no pointer was written, so this must still be a first run"); return }

        let home = try LaunchHomeResolver.resolveOrAdopt(
            chooseVault: { chosen }, pointerDirectory: s.pointer, cacheRoot: s.cache,
            legacyContainer: nil)

        #expect(home.vaultRoot.standardizedFileURL == chosen.standardizedFileURL)
        #expect(try HomeMarker.read(in: chosen)?.homeID == marker.homeID,
                "resuming must not mint a new identity")
    }

    /// A second launch resolves the pointer written by the first, rather than
    /// adopting anything new.
    @Test func aSecondLaunchResolvesTheExistingPointer() throws {
        let s = sandbox("launch4")
        defer { try? FileManager.default.removeItem(at: s.base) }
        let chosen = s.base.appendingPathComponent("Chosen")
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)

        let first = try LaunchHomeResolver.resolveOrAdopt(
            chooseVault: { chosen }, pointerDirectory: s.pointer, cacheRoot: s.cache,
            legacyContainer: nil)
        let elsewhere = s.base.appendingPathComponent("Elsewhere")
        let second = try LaunchHomeResolver.resolveOrAdopt(
            chooseVault: { elsewhere }, pointerDirectory: s.pointer, cacheRoot: s.cache,
            legacyContainer: nil)

        #expect(second.vaultRoot.standardizedFileURL == first.vaultRoot.standardizedFileURL)
        #expect(!FileManager.default.fileExists(atPath: elsewhere.path))
    }

    #if DEBUG
    @Test func debugFixtureRootParsing() {
        #expect(parseDebugFixtureRootArgument { @Sendable key in key == "AinkradFixtureRoot" ? "/tmp/test-fixture" : nil } == URL(fileURLWithPath: "/tmp/test-fixture").standardizedFileURL)
        #expect(parseDebugFixtureRootArgument { @Sendable key in key == "AinkradFixtureRoot" ? "   " : nil } == nil)
        #expect(parseDebugFixtureRootArgument { @Sendable _ in nil } == nil)
    }

    @Test func debugFixtureRootsCreateAllThreeSubdirectories() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("fixture-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let lookup: ArgumentLookup = { @Sendable key in key == "AinkradFixtureRoot" ? base.path : nil }

        let roots = try #require(try resolveDebugFixtureRoots(lookup))

        #expect(roots.pointerDirectory.lastPathComponent == "Pointer")
        #expect(roots.cacheRoot.lastPathComponent == "Cache")
        #expect(roots.defaultVaultRoot.lastPathComponent == "Vault")
        // Vault/ must exist before adopt() validates it, or the launch stalls on the recovery alert.
        for directory in [roots.pointerDirectory, roots.cacheRoot, roots.defaultVaultRoot] {
            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
            #expect(isDirectory.boolValue)
        }
    }

    @Test func debugFixtureRootThatIsAFileIsRefused() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("fixture-file-\(UUID().uuidString)")
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let lookup: ArgumentLookup = { @Sendable key in key == "AinkradFixtureRoot" ? file.path : nil }

        #expect(throws: DebugFixtureRootError.self) { try resolveDebugFixtureRoots(lookup) }
    }

    @Test func noFixtureArgumentMeansNoFixture() throws {
        #expect(try resolveDebugFixtureRoots { @Sendable _ in nil } == nil)
    }
    #endif
}
