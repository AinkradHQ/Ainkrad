import AinkradAppKit
import Foundation
import Testing

@testable import Ainkrad

/// Launch recovery: every non-`.unset` outcome used to reach `fatalError`, which
/// meant an unmounted external drive, a vault copied between Macs, or the far
/// more likely "I picked ~/Documents on first run" hard-crashed the app on every
/// launch with no in-app way back — the only escape was hand-deleting the
/// pointer file.
///
/// None of these paths has ever been executed by a human (nobody has clicked a
/// button in the first-run panel; assistive access was refused), so the decision
/// logic is deliberately a pure function and is tested here. Only
/// `LaunchHomeResolver.presentAlert` — the ~10 lines that drive `NSAlert` — is
/// left to inspection.
@Suite("Launch recovery")
struct LaunchRecoveryTests {

    // MARK: - The prompt table

    private func recoverableErrors(_ url: URL) -> [any Error] {
        [
            LaunchHomeResolver.Failure.vaultMissing(path: url.path),
            LaunchHomeResolver.Failure.notAnAinkradHome(path: url.path),
            HomeError.notEmpty(url),
            HomeError.nestedHome(url),
            HomeError.notWritable(url),
            HomeError.systemLocation(url),
            HomeError.doesNotExist(url),
        ]
    }

    @Test func everyReachableFailureOffersAWayForward() {
        let url = URL(fileURLWithPath: "/Users/someone/Documents")
        for error in recoverableErrors(url) {
            guard let prompt = LaunchRecovery.prompt(for: error) else {
                Issue.record("\(error) must produce a prompt, not a crash")
                continue
            }
            #expect(
                prompt.actions.contains(.chooseFolder),
                "\(error) must let the user choose a folder")
            #expect(prompt.actions.contains(.quit), "\(error) must let the user quit")
            #expect(prompt.buttons.count == prompt.actions.count)
            #expect(!prompt.title.isEmpty)
            #expect(
                prompt.message.contains(url.path),
                "the user has to be told WHICH folder: \(error)")
        }
    }

    /// Cancelling the chooser is a decision, not a failure — no alert, the caller
    /// exits cleanly.
    @Test func cancellingSetupProducesNoAlert() {
        #expect(LaunchRecovery.prompt(for: LaunchHomeResolver.Failure.setupCancelled) == nil)
    }

    /// An outcome the host cannot interpret must NOT invite the user to claim a
    /// folder over it — but must still be an alert, never a crash.
    @Test func anUninterpretableFailureOffersOnlyQuit() throws {
        let prompt = try #require(
            LaunchRecovery.prompt(for: LaunchHomeResolver.Failure.unrecognizedResolution))
        #expect(prompt.actions == [.quit])
        #expect(!prompt.actions.contains(.chooseFolder))
    }

    // MARK: - The recovery loop

    private func sandbox(_ label: String) -> (base: URL, pointer: URL, cache: URL) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        return (base, base.appendingPathComponent("pointer"), base.appendingPathComponent("cache"))
    }

    /// The most likely first-run mistake: pick a folder that already has files in
    /// it. Previously a permanent crash; now the user is told, picks an empty
    /// folder, and the app starts.
    @Test func choosingAPopulatedFolderIsRecoverable() throws {
        let s = sandbox("recover1")
        defer { try? FileManager.default.removeItem(at: s.base) }
        let populated = s.base.appendingPathComponent("MyNotes")
        try FileManager.default.createDirectory(at: populated, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: populated.appendingPathComponent("Note.md"))
        let empty = s.base.appendingPathComponent("Empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        var choices = [populated, empty]
        var prompts: [LaunchRecovery.Prompt] = []

        let home = try LaunchHomeResolver.resolveWithRecovery(
            chooseVault: { choices.isEmpty ? nil : choices.removeFirst() },
            present: {
                prompts.append($0)
                return .chooseFolder
            },
            pointerDirectory: s.pointer, cacheRoot: s.cache, legacyContainer: nil)

        #expect(prompts.count == 1)
        #expect(home.vaultRoot.standardizedFileURL == empty.standardizedFileURL)
        // The folder they mistakenly picked is untouched.
        #expect(
            Set(try FileManager.default.contentsOfDirectory(atPath: populated.path))
                == ["Note.md"])
    }

    /// An unreachable vault — an external volume not mounted at login. The user
    /// points the app at the folder; the app never picks one itself.
    @Test func aMissingVaultIsRecoverableByLocatingIt() throws {
        let s = sandbox("recover2")
        defer { try? FileManager.default.removeItem(at: s.base) }
        let original = s.base.appendingPathComponent("Vault")
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        _ = try AinkradHome.adopt(original, pointerDirectory: s.pointer, cacheRoot: s.cache)
        let moved = s.base.appendingPathComponent("MovedVault")
        try FileManager.default.moveItem(at: original, to: moved)

        var prompts: [LaunchRecovery.Prompt] = []
        let home = try LaunchHomeResolver.resolveWithRecovery(
            chooseVault: { moved },
            present: {
                prompts.append($0)
                return .chooseFolder
            },
            pointerDirectory: s.pointer, cacheRoot: s.cache, legacyContainer: nil)

        #expect(prompts.count == 1)
        #expect(home.vaultRoot.standardizedFileURL == moved.standardizedFileURL)
        // Re-adopting a folder that is already a Home keeps its identity.
        #expect(try HomeMarker.read(in: moved) != nil)
    }

    /// A vault copied from another Mac: the folder is there, the `homeID` doesn't
    /// match. Adopting the same folder deliberately is the fix.
    @Test func aForeignVaultIsRecoverableByAdoptingIt() throws {
        let s = sandbox("recover3")
        defer { try? FileManager.default.removeItem(at: s.base) }
        let vault = s.base.appendingPathComponent("Vault")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        _ = try AinkradHome.adopt(vault, pointerDirectory: s.pointer, cacheRoot: s.cache)
        // Same path, different identity — what a copied vault looks like.
        try HomeMarker().write(to: vault)

        var prompts: [LaunchRecovery.Prompt] = []
        let home = try LaunchHomeResolver.resolveWithRecovery(
            chooseVault: { vault },
            present: {
                prompts.append($0)
                return .chooseFolder
            },
            pointerDirectory: s.pointer, cacheRoot: s.cache, legacyContainer: nil)

        #expect(prompts.count == 1)
        #expect(home.vaultRoot.standardizedFileURL == vault.standardizedFileURL)
        // The pointer now agrees with the marker: a second launch is clean.
        guard case .ready = AinkradHome.resolve(pointerDirectory: s.pointer, cacheRoot: s.cache)
        else {
            Issue.record("recovery must leave a resolvable Home")
            return
        }
    }

    /// Quit is a clean exit, not a crash — and it must change nothing on disk.
    @Test func quittingFromTheAlertWritesNothing() throws {
        let s = sandbox("recover4")
        defer { try? FileManager.default.removeItem(at: s.base) }
        let populated = s.base.appendingPathComponent("MyNotes")
        try FileManager.default.createDirectory(at: populated, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: populated.appendingPathComponent("Note.md"))

        #expect(throws: LaunchHomeResolver.Failure.userQuit) {
            _ = try LaunchHomeResolver.resolveWithRecovery(
                chooseVault: { populated }, present: { _ in .quit },
                pointerDirectory: s.pointer, cacheRoot: s.cache, legacyContainer: nil)
        }

        guard case .unset = AinkradHome.resolve(pointerDirectory: s.pointer, cacheRoot: s.cache)
        else {
            Issue.record("quitting must leave no pointer")
            return
        }
        #expect(
            !FileManager.default.fileExists(
                atPath: populated.appendingPathComponent(".ainkrad-home").path))
    }

    /// Dismissing the folder chooser during recovery is still a cancel, and still
    /// leaves nothing behind.
    @Test func cancellingTheChooserDuringRecoveryCancelsSetup() throws {
        let s = sandbox("recover5")
        defer { try? FileManager.default.removeItem(at: s.base) }
        let populated = s.base.appendingPathComponent("MyNotes")
        try FileManager.default.createDirectory(at: populated, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: populated.appendingPathComponent("Note.md"))

        var choices: [URL?] = [populated, nil]
        #expect(throws: LaunchHomeResolver.Failure.setupCancelled) {
            _ = try LaunchHomeResolver.resolveWithRecovery(
                chooseVault: { choices.isEmpty ? nil : choices.removeFirst() },
                present: { _ in .chooseFolder },
                pointerDirectory: s.pointer, cacheRoot: s.cache, legacyContainer: nil)
        }
        guard case .unset = AinkradHome.resolve(pointerDirectory: s.pointer, cacheRoot: s.cache)
        else {
            Issue.record("a cancelled recovery must leave no pointer")
            return
        }
    }

    /// Recovery must never quietly pick a location. A successful launch is only
    /// ever reached through a folder that came back from `chooseVault`.
    @Test func recoveryNeverInventsALocation() throws {
        let s = sandbox("recover6")
        defer { try? FileManager.default.removeItem(at: s.base) }
        let vault = s.base.appendingPathComponent("Vault")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        _ = try AinkradHome.adopt(vault, pointerDirectory: s.pointer, cacheRoot: s.cache)
        try FileManager.default.removeItem(at: vault)

        // The user is offered recovery and declines to pick anything.
        #expect(throws: LaunchHomeResolver.Failure.setupCancelled) {
            _ = try LaunchHomeResolver.resolveWithRecovery(
                chooseVault: { nil }, present: { _ in .chooseFolder },
                pointerDirectory: s.pointer, cacheRoot: s.cache, legacyContainer: nil)
        }
        // The original pointer is untouched, and no folder was created anywhere.
        #expect(!FileManager.default.fileExists(atPath: vault.path))
        // Only the pointer directory and the cache root the first adopt made —
        // no vault appeared anywhere.
        let entries = Set(try FileManager.default.contentsOfDirectory(atPath: s.base.path))
        #expect(entries.isSubset(of: ["pointer", "cache"]), "recovery created: \(entries)")
    }

    /// A resolvable Home never shows an alert and never asks for a folder.
    @Test func aHealthyLaunchNeverPrompts() throws {
        let s = sandbox("recover7")
        defer { try? FileManager.default.removeItem(at: s.base) }
        let vault = s.base.appendingPathComponent("Vault")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        _ = try AinkradHome.adopt(vault, pointerDirectory: s.pointer, cacheRoot: s.cache)

        var prompted = 0
        var chose = 0
        let home = try LaunchHomeResolver.resolveWithRecovery(
            chooseVault: {
                chose += 1
                return nil
            },
            present: { _ in
                prompted += 1
                return .quit
            },
            pointerDirectory: s.pointer, cacheRoot: s.cache, legacyContainer: nil)

        #expect(prompted == 0)
        #expect(chose == 0)
        #expect(home.vaultRoot.standardizedFileURL == vault.standardizedFileURL)
    }
}
