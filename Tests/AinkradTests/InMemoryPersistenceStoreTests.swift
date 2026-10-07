import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

private struct SampleDoc: PersistableDocument {
    static let documentID = "sample"
    var name: String
    var count: Int
}

@Suite("InMemoryPersistenceStore")
struct InMemoryPersistenceStoreTests {
    @Test("load returns nil before any save")
    func loadNilWhenEmpty() {
        let store = InMemoryPersistenceStore()
        #expect(store.load(SampleDoc.self) == nil)
    }

    @Test("save then load round-trips the document")
    func saveThenLoad() {
        let store = InMemoryPersistenceStore()
        store.save(SampleDoc(name: "a", count: 3))
        #expect(store.load(SampleDoc.self) == SampleDoc(name: "a", count: 3))
    }

    @Test("delete removes a saved document")
    func deleteRemoves() {
        let store = InMemoryPersistenceStore()
        store.save(SampleDoc(name: "a", count: 3))
        store.delete(SampleDoc.self)
        #expect(store.load(SampleDoc.self) == nil)
    }
}
