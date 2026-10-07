import Foundation

/// A `PersistenceStore` kept entirely in memory. Encodes each document to
/// `Data` on save (so it exercises the same `Codable` path as disk) and decodes
/// on load. Migration is not exercised in memory — stored payloads are always
/// at the current version. Primarily for tests, and usable as a null store.
///
/// Locked for the same reason as `FileDocumentStore`: `PersistenceStore` is now
/// `Sendable`, and this store is handed to the same off-main call sites in
/// tests. An unsynchronized dictionary here would just relocate the race into
/// the test suite, where it is hardest to see.
///
/// `@unchecked Sendable` invariant: `storage` is the only mutable state and is
/// touched only while holding `lock`.
public final class InMemoryPersistenceStore: PersistenceStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    public init() {}

    public func load<T: PersistableDocument>(_ type: T.Type) -> T? {
        guard let data = lock.withLock({ storage[T.documentID] }) else { return nil }
        return try? PersistenceCoding.decoder.decode(T.self, from: data)
    }

    public func save<T: PersistableDocument>(_ document: T) {
        guard let data = try? PersistenceCoding.encoder.encode(document) else { return }
        lock.withLock { storage[T.documentID] = data }
    }

    public func delete<T: PersistableDocument>(_ type: T.Type) {
        lock.withLock { storage[T.documentID] = nil }
    }
}
