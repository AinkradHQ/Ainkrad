// Sources/Ainkrad/Core/AgentKit/Autonomy/EditJournal.swift
import Foundation

struct EditJournalEntry: Sendable, Equatable, Identifiable {
    let id: UUID
    let path: String
    let before: String
    let after: String
    let existedBefore: Bool
    let date: Date
}

/// A per-session ledger of file edits so a turn's edits can be undone. In-memory:
/// undo/redo is a within-session operation (the on-disk file is the effect).
/// Recording is best-effort — a journaling failure must never fail the edit
/// that triggered it (see `EditFileTool.execute`).
@MainActor
final class EditJournal {
    private(set) var entries: [EditJournalEntry] = []
    var count: Int { entries.count }

    @discardableResult
    func record(path: String, before: String, after: String, existedBefore: Bool) -> UUID {
        let entry = EditJournalEntry(
            id: UUID(), path: path, before: before,
            after: after, existedBefore: existedBefore, date: Date())
        entries.append(entry)
        return entry.id
    }

    /// Restores `before` (or deletes the file when the edit created it) and
    /// drops the entry. A file that no longer exists / was changed externally
    /// since the edit is handled gracefully — best-effort, never throws.
    @discardableResult
    func revert(_ id: UUID) -> Bool {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return false }
        let ok = apply(entries[idx])
        entries.remove(at: idx)
        return ok
    }

    /// Reverts every entry from `index` (inclusive) to the end, in reverse
    /// order — the per-turn undo hook. Multiple edits to the same file unwind
    /// most-recent-first. Returns how many reverts succeeded.
    func revertEntries(after index: Int) -> Int {
        guard index < entries.count else { return 0 }
        var reverted = 0
        for i in stride(from: entries.count - 1, through: index, by: -1) {
            if apply(entries[i]) { reverted += 1 }
            entries.remove(at: i)
        }
        return reverted
    }

    /// Best-effort: a missing/externally-changed file just means the write or
    /// delete no-ops rather than restoring anything — never crashes or throws.
    @discardableResult
    private func apply(_ entry: EditJournalEntry) -> Bool {
        if entry.existedBefore {
            do {
                try entry.before.write(toFile: entry.path, atomically: true, encoding: .utf8)
                return true
            } catch {
                return false
            }
        } else {
            do {
                if FileManager.default.fileExists(atPath: entry.path) {
                    try FileManager.default.removeItem(atPath: entry.path)
                }
                return true
            } catch {
                return false
            }
        }
    }
}
