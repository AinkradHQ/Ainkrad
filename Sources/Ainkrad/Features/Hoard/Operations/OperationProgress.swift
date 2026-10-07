import Foundation
import Observation

struct OperationFailure: Sendable, Equatable {
    var url: URL
    var reason: String
}

struct OperationResult: Sendable, Equatable {
    var succeeded: Int
    var skipped: Int
    var failures: [OperationFailure]
    var wasCancelled: Bool
}

/// Live state for one running job, surfaced by the operations panel.
///
/// Progress is per ITEM, not per byte. Byte-level progress would mean
/// reimplementing `FileManager`'s copy semantics — symlinks, permissions,
/// extended attributes, package directories — in a chunked read/write loop.
/// Per-item is honest about what it measures; byte-level is a later refinement
/// and the panel says so rather than implying precision it doesn't have.
@MainActor
@Observable
final class OperationProgress: Identifiable {
    let id = UUID()
    let label: String
    let totalItems: Int

    private(set) var completedItems = 0
    private(set) var isCancelled = false
    private(set) var failures: [OperationFailure] = []
    private(set) var isFinished = false

    init(label: String, totalItems: Int) {
        self.label = label
        self.totalItems = totalItems
    }

    var fraction: Double {
        totalItems > 0 ? Double(completedItems) / Double(totalItems) : 0
    }

    func advance() { completedItems += 1 }
    func recordFailure(_ failure: OperationFailure) { failures.append(failure) }
    func finish() { isFinished = true }

    /// Cooperative: the engine checks this between items. An in-flight
    /// `FileManager` copy of a huge file still runs to completion — killing it
    /// midway would leave a truncated file with no record of it.
    func cancel() { isCancelled = true }
}
