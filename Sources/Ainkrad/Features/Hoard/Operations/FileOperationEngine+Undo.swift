import Foundation

/// Why an undo could not be applied. Both cases are surfaced to the user —
/// silently doing nothing is what makes an undo stack untrustworthy.
enum UndoRefusal: Equatable {
    /// A file this entry touches has changed since the operation. Auto-
    /// inverting would clobber newer content in the name of undo, which is
    /// worse than not undoing.
    case externallyModified(URL)
    /// The volume is gone (ejected disk). The entry is dropped rather than
    /// left as a landmine that fails at the next ⌘Z.
    case unavailable(URL)

    var message: String {
        switch self {
        case .externallyModified(let url):
            return "“\(url.lastPathComponent)” changed since then — undo would overwrite newer content."
        case .unavailable(let url):
            return "“\(url.lastPathComponent)” is no longer available — that step was dropped."
        }
    }
}

extension FileOperationEngine {
    /// Applies the most recent inverse, or explains why it can't.
    @discardableResult
    func undo() -> UndoRefusal? {
        guard let entry = undoStack.entries.last else { return nil }

        if let refusal = refusal(for: entry) {
            // An unavailable volume is permanent for this entry: drop it so
            // the next ⌘Z reaches something that can actually be applied. An
            // externally-modified entry STAYS — the user may revert the file
            // and try again.
            if case .unavailable = refusal { undoStack.drop(entry.id) }
            return refusal
        }

        _ = undoStack.popForUndo()
        apply(entry.action)
        // Push the entry UNCHANGED: redo now re-runs the recorded forward
        // operation, so the inverse's shape is irrelevant. The old
        // `redoCounterpart` rebuilt the entry and silently dropped its `redo`
        // spec, which is why move and rename could not be redone at all.
        undoStack.pushRedo(entry)
        return nil
    }

    /// Re-runs the ORIGINAL operation.
    ///
    /// The first cut re-applied the inverse, which for a copy meant deleting
    /// files that were already gone — a redo that structurally could not redo.
    /// Re-submitting the recorded forward operation also means the redone work
    /// lands on the undo stack again, so ⌘Z after ⌘⇧Z behaves.
    func redo() async -> UndoRefusal? {
        guard let entry = undoStack.redoEntries.last else { return nil }
        guard let spec = entry.redo else {
            // Nothing to replay (an entry from before redo specs existed);
            // drop it rather than leave a button that does nothing.
            _ = undoStack.popForRedo()
            return nil
        }
        _ = undoStack.popForRedo()

        let operation: FileOperation
        switch spec.kind {
        case .copy:
            operation = FileOperation(
                kind: .copy, sources: spec.sources,
                destinationDirectory: spec.destinationDirectory,
                policy: spec.policy)
        case .move:
            operation = FileOperation(
                kind: .move, sources: spec.sources,
                destinationDirectory: spec.destinationDirectory,
                policy: spec.policy)
        case .rename:
            operation = FileOperation(
                kind: .rename(newName: spec.name ?? ""),
                sources: spec.sources, destinationDirectory: nil)
        case .createFolder:
            operation = FileOperation(
                kind: .createFolder(name: spec.name ?? ""),
                sources: [], destinationDirectory: spec.destinationDirectory)
        case .trash:
            operation = FileOperation(
                kind: .trash, sources: spec.sources,
                destinationDirectory: nil)
        case .archive:
            operation = FileOperation(
                kind: .archive(name: spec.name ?? ""),
                sources: spec.sources,
                destinationDirectory: spec.destinationDirectory)
        case .extract:
            operation = FileOperation(
                kind: .extract, sources: spec.sources,
                destinationDirectory: spec.destinationDirectory)
        case .batchRename:
            operation = FileOperation(
                kind: .batchRename(newNames: spec.names ?? []),
                sources: spec.sources, destinationDirectory: nil)
        }
        _ = await submit(operation)
        return nil
    }

    /// The check that makes undo trustworthy: refuse when the world moved on.
    ///
    /// Only files that STILL EXIST can have been externally modified. A
    /// restore-from-trash inverse names paths that are absent by definition —
    /// that is what being in the Trash means — so treating "missing" as a
    /// problem refused exactly the undo the Trash exists to make possible.
    ///
    /// Availability is judged on the enclosing DIRECTORY, not the item: asking
    /// a vanished path for its volume tells you nothing, while asking its
    /// parent tells you whether the disk is still mounted.
    private func refusal(for entry: InverseOperation) -> UndoRefusal? {
        for url in entry.affectedURLs {
            if let modified = mutatorModificationDate(url) {
                // A tolerance, not equality: filesystem timestamps have coarse
                // resolution and the write completes microseconds after we
                // record.
                if modified.timeIntervalSince(entry.recordedAt) > 1.0 {
                    return .externallyModified(url)
                }
                continue
            }
            // Absent. Only a genuinely unreachable volume is a refusal.
            if mutatorVolumeIdentifier(url.deletingLastPathComponent()) == nil {
                return .unavailable(url)
            }
        }
        return nil
    }

    private func apply(_ action: InverseAction) {
        switch action {
        case .moveBack(let items):
            for item in items { try? mutatorMove(item.from, item.to) }
        case .delete(let urls):
            for url in urls { try? mutatorRemove(url) }
        case .restoreFromTrash(let items):
            for item in items { try? trashRestore(item.inTrash, item.original) }
        case .composite(let actions):
            // Order matters: remove what was written BEFORE restoring what was
            // displaced, or the restore collides with the file still there.
            for nested in actions { apply(nested) }
        }
    }
}
