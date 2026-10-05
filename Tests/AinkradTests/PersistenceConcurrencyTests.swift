import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

private struct ConcurrentDoc: PersistableDocument {
    static let documentID = "concurrent-sample"
    var value: Int
}

private struct OtherConcurrentDoc: PersistableDocument {
    static let documentID = "concurrent-other"
    var text: String
}

/// Wave 1-C: `FileDocumentStore`'s write-through cache was an unsynchronized
/// dictionary reached from off the main actor by five `nonisolated(unsafe)`
/// call sites — a data race the compiler had been told to ignore.
///
/// These tests hammer the store from many concurrent tasks. They are not a
/// *proof* of thread safety (no test is; that needs TSan), but under the old
/// implementation they reliably tripped the sanitizer and could crash outright
/// on a dictionary rehash. Under the lock they are deterministic.
@Suite("PersistenceStore concurrency", .timeLimit(.minutes(1)))
struct PersistenceConcurrencyTests {

    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ainkrad-concurrency-\(UUID().uuidString)")
    }

    @Test("Concurrent saves and loads of the same document never corrupt the cache")
    func concurrentSameDocument() async {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileDocumentStore(rootURL: root)
        store.save(ConcurrentDoc(value: 0))

        await withTaskGroup(of: Void.self) { group in
            for i in 1...200 {
                group.addTask { store.save(ConcurrentDoc(value: i)) }
                group.addTask { _ = store.load(ConcurrentDoc.self) }
            }
        }

        // Whichever writer won, the store must return a well-formed document
        // in the written range — not a torn read or a crash.
        let final = store.load(ConcurrentDoc.self)
        #expect(final != nil)
        #expect((0...200).contains(final?.value ?? -1))
    }

    @Test("Concurrent access to different documents is safe")
    func concurrentDifferentDocuments() async {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileDocumentStore(rootURL: root)

        await withTaskGroup(of: Void.self) { group in
            for i in 1...100 {
                group.addTask { store.save(ConcurrentDoc(value: i)) }
                group.addTask { store.save(OtherConcurrentDoc(text: "v\(i)")) }
                group.addTask { _ = store.load(OtherConcurrentDoc.self) }
                group.addTask { store.clearCache() }
            }
        }

        // clearCache races with the writes, so the cache may be empty — but the
        // last durable write must still be readable from disk.
        #expect(store.load(ConcurrentDoc.self) != nil)
        #expect(store.load(OtherConcurrentDoc.self) != nil)
    }

    @Test("The same guarantees hold for the in-memory store")
    func inMemoryStoreIsSafe() async {
        let store = InMemoryPersistenceStore()
        await withTaskGroup(of: Void.self) { group in
            for i in 1...200 {
                group.addTask { store.save(ConcurrentDoc(value: i)) }
                group.addTask { _ = store.load(ConcurrentDoc.self) }
                group.addTask { store.save(OtherConcurrentDoc(text: "v\(i)")) }
            }
        }
        #expect(store.load(ConcurrentDoc.self) != nil)
    }

    @Test("Delete racing with save leaves the store consistent, never crashed")
    func deleteRacingSave() async {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileDocumentStore(rootURL: root)
        await withTaskGroup(of: Void.self) { group in
            for i in 1...100 {
                group.addTask { store.save(ConcurrentDoc(value: i)) }
                group.addTask { store.delete(ConcurrentDoc.self) }
            }
        }
        // Either outcome is legitimate; a crash or a decode of freed memory is not.
        let result = store.load(ConcurrentDoc.self)
        if let result { #expect((1...100).contains(result.value)) }
    }
}
