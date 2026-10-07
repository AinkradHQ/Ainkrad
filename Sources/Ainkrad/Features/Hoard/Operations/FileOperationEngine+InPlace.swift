import Foundation

/// The in-place edits: rename, batch rename and new folder. Each runs on the
/// main actor (a rename is a metadata change, not a byte copy) and records its
/// inverse only for what actually landed.
extension FileOperationEngine {
    func rename(_ operation: FileOperation, to newName: String) -> OperationResult {
        guard let source = operation.sources.first else {
            return OperationResult(succeeded: 0, skipped: 0, failures: [], wasCancelled: false)
        }
        let destination = source.deletingLastPathComponent().appendingPathComponent(newName)
        guard !mutatorFileExists(destination) else {
            return OperationResult(
                succeeded: 0, skipped: 0,
                failures: [
                    OperationFailure(
                        url: destination, reason: "A file named “\(newName)” already exists.")
                ],
                wasCancelled: false)
        }
        do {
            try mutatorMove(source, destination)
            undoStack.push(.forRename(from: source, to: destination))
            return OperationResult(succeeded: 1, skipped: 0, failures: [], wasCancelled: false)
        } catch {
            return OperationResult(
                succeeded: 0, skipped: 0,
                failures: [
                    OperationFailure(
                        url: source, reason: error.localizedDescription)
                ], wasCancelled: false)
        }
    }

    /// Many renames, ONE undo entry.
    ///
    /// Submitting a rename per row (what the batch sheet did first) works, but
    /// it means undoing a 200-file rename is 200 ⌘Z — technically reversible,
    /// practically not. Recording a single inverse over every pair that landed
    /// makes ⌘Z put the whole batch back.
    ///
    /// A row that fails does NOT abort the rest, matching `transfer`: the
    /// inverse covers exactly what completed, so a partial batch is still
    /// wholly undoable.
    func batchRename(
        _ operation: FileOperation, to newNames: [String],
        progress: OperationProgress
    ) -> OperationResult {
        guard newNames.count == operation.sources.count else {
            // Positional arrays out of step would rename files under each
            // other's names — refuse the whole thing rather than guess.
            return OperationResult(
                succeeded: 0, skipped: 0,
                failures: [
                    OperationFailure(
                        url: operation.sources.first ?? URL(fileURLWithPath: "/"),
                        reason: "Batch rename received \(newNames.count) names for \(operation.sources.count) files.")
                ],
                wasCancelled: false)
        }

        var moved: [MovedItem] = []
        var failures: [OperationFailure] = []

        for (source, newName) in zip(operation.sources, newNames) {
            if progress.isCancelled { break }
            let destination = source.deletingLastPathComponent().appendingPathComponent(newName)

            guard !mutatorFileExists(destination) else {
                // The planner already filtered collisions, but the disk can
                // change between preview and apply.
                failures.append(
                    OperationFailure(
                        url: destination, reason: "A file named “\(newName)” already exists."))
                progress.advance()
                continue
            }
            do {
                try mutatorMove(source, destination)
                moved.append(MovedItem(from: source, to: destination))
            } catch {
                failures.append(OperationFailure(url: source, reason: error.localizedDescription))
            }
            progress.advance()
        }

        if !moved.isEmpty { undoStack.push(.forBatchRename(items: moved)) }
        return OperationResult(
            succeeded: moved.count, skipped: 0,
            failures: failures, wasCancelled: progress.isCancelled)
    }

    func createFolder(_ operation: FileOperation, named name: String) -> OperationResult {
        guard let parent = operation.destinationDirectory else {
            return OperationResult(succeeded: 0, skipped: 0, failures: [], wasCancelled: false)
        }
        let url = parent.appendingPathComponent(name)
        guard !mutatorFileExists(url) else {
            return OperationResult(
                succeeded: 0, skipped: 0,
                failures: [
                    OperationFailure(
                        url: url, reason: "A folder named “\(name)” already exists.")
                ],
                wasCancelled: false)
        }
        do {
            try mutatorCreateDirectory(url)
            undoStack.push(.forCreateFolder(at: url))
            return OperationResult(succeeded: 1, skipped: 0, failures: [], wasCancelled: false)
        } catch {
            return OperationResult(
                succeeded: 0, skipped: 0,
                failures: [
                    OperationFailure(
                        url: url, reason: error.localizedDescription)
                ], wasCancelled: false)
        }
    }
}
