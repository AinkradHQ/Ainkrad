import AinkradHostRuntime
import Foundation
import Observation

struct UndoStackDocument: PersistableDocument {
    static let documentID = "files-undo"

    var entries: [InverseOperation] = []
    var redoEntries: [InverseOperation] = []

    init(entries: [InverseOperation] = [], redoEntries: [InverseOperation] = []) {
        self.entries = entries
        self.redoEntries = redoEntries
    }
}

/// The single funnel every mutation passes through — keyboard, context menu and
/// (from M4) assistant-initiated operations all push here, so ⌘Z reverses them
/// identically regardless of origin.
@MainActor
@Observable
final class UndoStack {
    /// Cap chosen so the stack stays useful without growing the persisted
    /// document unboundedly across a long session.
    static let maximumDepth = 100

    /// DIRECTLY STORED, persisted in `didSet` — the M1 lesson. Computed
    /// accessors over a private document struct silently fail to register
    /// SwiftUI dependencies, and `canUndo` drives a live toolbar/menu state.
    private(set) var entries: [InverseOperation] = [] {
        didSet { persist() }
    }
    private(set) var redoEntries: [InverseOperation] = [] {
        didSet { persist() }
    }

    private let persistence: PersistenceStore

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        let document = persistence.load(UndoStackDocument.self) ?? UndoStackDocument()
        self.entries = document.entries
        self.redoEntries = document.redoEntries
    }

    var canUndo: Bool { !entries.isEmpty }
    var canRedo: Bool { !redoEntries.isEmpty }
    var undoLabel: String? { entries.last?.label }
    var redoLabel: String? { redoEntries.last?.label }

    /// Records a completed operation. Clears the redo stack: performing new
    /// work abandons the branch of history that redo would have replayed, and
    /// keeping those entries would let ⌘⇧Z reapply work from a timeline the
    /// user has left.
    func push(_ inverse: InverseOperation) {
        redoEntries.removeAll()
        entries.append(inverse)
        if entries.count > Self.maximumDepth {
            entries.removeFirst(entries.count - Self.maximumDepth)
        }
    }

    func popForUndo() -> InverseOperation? {
        entries.popLast()
    }

    func pushRedo(_ inverse: InverseOperation) {
        redoEntries.append(inverse)
        if redoEntries.count > Self.maximumDepth {
            redoEntries.removeFirst(redoEntries.count - Self.maximumDepth)
        }
    }

    func popForRedo() -> InverseOperation? {
        redoEntries.popLast()
    }

    /// Removes an entry that can no longer be applied — an unmounted volume,
    /// say. Dropping it beats leaving a landmine that fails at ⌘Z time.
    func drop(_ id: InverseOperation.ID) {
        entries.removeAll { $0.id == id }
    }

    func clear() {
        entries.removeAll()
        redoEntries.removeAll()
    }

    private func persist() {
        persistence.save(UndoStackDocument(entries: entries, redoEntries: redoEntries))
    }
}
