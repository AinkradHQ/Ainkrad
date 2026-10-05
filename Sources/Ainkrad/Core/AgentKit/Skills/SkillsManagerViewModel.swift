import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// The logic behind the Skills settings tabs. Owns the local-skill editor drafts and
/// the bind/unbind flow; kept separate from the view body so the
/// bind→`CommandRegistry` re-sync logic is unit-testable without SwiftUI.
///
/// `resyncCommands` is the seam that fixes the Task 12 gap: bootstrap only
/// registered the skill `/name` commands into `CommandRegistry` once, at
/// launch, so a bind/unbind made here — at runtime — would otherwise sit
/// invisibly in `SkillCommandStore` until the next relaunch. Every mutating
/// action below (bind, unbind, delete-a-bound-skill) calls it so `/name`
/// starts/stops resolving immediately.
@MainActor
@Observable
final class SkillsManagerViewModel {
    let registry: SkillRegistry
    let store: SkillCommandStore
    private let resyncCommands: () -> Void
    private let fileManager: FileManager

    /// In-progress edits for LOCAL skills' raw `SKILL.md` text, keyed by
    /// skill name. Populated lazily from disk on first access.
    private(set) var drafts: [String: String] = [:]
    /// Set when `bind(command:toSkill:)` rejects a name — surfaced by the
    /// view instead of silently no-op'ing (mirrors `SkillCommandStore.bind`'s
    /// guarded-but-silent contract; the manager is where the user finds out).
    private(set) var bindError: String?

    init(
        registry: SkillRegistry, store: SkillCommandStore, resyncCommands: @escaping () -> Void,
        fileManager: FileManager = .default
    ) {
        self.registry = registry
        self.store = store
        self.resyncCommands = resyncCommands
        self.fileManager = fileManager
    }

    /// Count of pending `_proposed/` drafts — drives the manager-entry badge so a
    /// freshly proposed/improved skill is visible without opening the manager.
    var proposalCount: Int { registry.proposals().count }

    // MARK: - Active skills / local editor

    private func onDiskText(_ skill: Skill) -> String {
        (try? String(contentsOf: registry.paths.skillFile(skill.name), encoding: .utf8)) ?? ""
    }

    func draft(for skill: Skill) -> String {
        if let existing = drafts[skill.name] { return existing }
        let text = onDiskText(skill)
        drafts[skill.name] = text
        return text
    }

    func setDraft(_ text: String, for skill: Skill) { drafts[skill.name] = text }

    func hasUnsavedChanges(_ skill: Skill) -> Bool { draft(for: skill) != onDiskText(skill) }

    /// Overwrites the local skill's `SKILL.md` with the current draft. A
    /// no-op when unchanged, mirroring `MemoryUIViewModel.save`.
    func save(_ skill: Skill) {
        let text = draft(for: skill)
        guard text != onDiskText(skill) else { return }
        try? registry.writeLocal(text, name: skill.name)
        drafts[skill.name] = nil
    }

    /// Deletes an active skill's directory and reloads. Also re-syncs
    /// commands: a deleted skill may have had a `/name` bound to it, which
    /// should immediately read as a broken binding rather than stay wired to
    /// a stale in-memory closure until relaunch.
    func delete(_ skill: Skill) {
        try? fileManager.removeItem(at: registry.paths.skillDir(skill.name))
        drafts[skill.name] = nil
        registry.reload()
        resyncCommands()
    }

    // MARK: - Proposals

    func approve(_ proposal: SkillProposal) { try? registry.approve(name: proposal.name) }
    func discard(_ proposal: SkillProposal) { try? registry.discard(name: proposal.name) }

    // MARK: - Commands

    /// Binds `command` to `skillName` and re-syncs the live `CommandRegistry`.
    /// Rejects — with `bindError` set for the view to surface — exactly the
    /// names `SkillCommandStore.bind` itself would silently refuse (unsafe
    /// slug, or a builtin-shadowing name): checked here BEFORE calling
    /// `store.bind` so the rejection reason can be reported instead of the
    /// caller just observing nothing happened.
    @discardableResult
    func bind(command: String, toSkill skillName: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            bindError = "Enter a command name to bind."
            return false
        }
        guard SkillCommandStore.isValidCommandName(trimmed) else {
            bindError =
                "\"/\(trimmed)\" is invalid — command names must be a lowercase slug (letters, numbers, \"-\") and can't shadow a builtin like /new or /model."
            return false
        }
        store.bind(command: trimmed, toSkill: skillName)
        resyncCommands()
        bindError = nil
        return true
    }

    func unbind(_ command: String) {
        store.unbind(command: command)
        resyncCommands()
    }

    func clearBindError() { bindError = nil }
}
