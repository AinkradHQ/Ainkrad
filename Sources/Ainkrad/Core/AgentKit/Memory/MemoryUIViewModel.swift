import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// View-model for `MemoryUIView`: owns the three files' in-progress drafts
/// and the save/undo actions, kept separate from the view body so the
/// edit/undo logic is unit-testable without instantiating SwiftUI.
///
/// Save is an overwrite (not `MemoryService.write`'s append semantics — the
/// draft already contains the whole file's text), so it goes through
/// `store.write` + `log.record` directly with provenance `.edit`, mirroring
/// `MemoryConsolidator`'s own full-content-replace pattern. A no-op save
/// (draft unchanged from disk) skips the write/reindex/log churn.
@MainActor
@Observable
final class MemoryUIViewModel {
    let service: MemoryService
    private(set) var drafts: [MemoryFile: String]

    init(service: MemoryService) {
        self.service = service
        var initial: [MemoryFile: String] = [:]
        for file in MemoryFile.allCases { initial[file] = service.store.read(file) }
        self.drafts = initial
    }

    func draft(for file: MemoryFile) -> String { drafts[file] ?? "" }

    func setDraft(_ text: String, for file: MemoryFile) { drafts[file] = text }

    /// Whether `file`'s draft differs from what's currently on disk.
    func hasUnsavedChanges(_ file: MemoryFile) -> Bool {
        draft(for: file) != service.store.read(file)
    }

    /// Persists the draft as an edit, logging it with provenance `.edit` so
    /// it's reviewable/undoable in the log timeline. No-op when unchanged.
    func save(_ file: MemoryFile) {
        let prior = service.store.read(file)
        let text = draft(for: file)
        guard text != prior else { return }
        service.store.write(text, to: file)  // onChange reindexes
        service.log.record(file: file, provenance: .edit, addedText: text, priorSnapshot: prior)
    }

    var logEntries: [MemoryLogEntry] { service.log.entries() }

    /// Undoes a log entry and refreshes every draft from disk afterward, so
    /// an open editor for the restored file doesn't keep showing stale text
    /// (or clobber the restore on its next Save).
    func undo(_ id: UUID) {
        service.log.undo(id)
        for file in MemoryFile.allCases { drafts[file] = service.store.read(file) }
    }
}
