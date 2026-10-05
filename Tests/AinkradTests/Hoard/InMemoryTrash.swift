import Foundation

@testable import Ainkrad

/// Disk-free `Trashing` for unit tests. Records what was trashed and what was
/// restored, so engine tests can assert that a destructive path went through
/// the Trash rather than unlinking.
final class InMemoryTrash: Trashing, @unchecked Sendable {
    struct NotInTrash: Error { let url: URL }

    private var items: [URL: URL] = [:]  // trash location → original
    private(set) var restored: [URL] = []

    func trash(_ url: URL) throws -> URL {
        let destination = URL(fileURLWithPath: "/in-memory-trash")
            .appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
        items[destination] = url
        return destination
    }

    func restore(from trashURL: URL, to original: URL) throws {
        guard items.removeValue(forKey: trashURL) != nil else {
            throw NotInTrash(url: trashURL)
        }
        restored.append(original)
    }

    func contains(_ trashURL: URL) -> Bool { items[trashURL] != nil }
    var trashedCount: Int { items.count }
}
