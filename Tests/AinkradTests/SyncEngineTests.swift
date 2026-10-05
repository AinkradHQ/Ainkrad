import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

private struct SampleDoc: PersistableDocument {
    static let documentID = "sample"
    var name: String
}

private final class SpySyncEngine: SyncEngine {
    private(set) var changes: [String] = []
    private(set) var started = false
    func documentDidChange(id: String, data: Data) { changes.append(id) }
    func start() { started = true }
}

@Suite("SyncEngine seam")
final class SyncEngineTests {
    let root: URL
    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ainkrad-tests-\(UUID().uuidString)")
    }
    deinit { try? FileManager.default.removeItem(at: root) }

    @Test("saving a document notifies the sync engine with its id")
    func saveNotifiesSyncEngine() {
        let store = FileDocumentStore(rootURL: root)
        let spy = SpySyncEngine()
        store.syncEngine = spy
        store.save(SampleDoc(name: "a"))
        #expect(spy.changes == ["sample"])
    }

    @Test("NoOpSyncEngine ignores notifications without crashing")
    func noOpDoesNothing() {
        let store = FileDocumentStore(rootURL: root)
        // Hold a strong ref: syncEngine is weak, so a freshly-constructed
        // engine assigned inline would deallocate before save fires and the
        // no-op notification path would never actually run.
        let engine = NoOpSyncEngine()
        store.syncEngine = engine
        store.save(SampleDoc(name: "a"))
        #expect(store.load(SampleDoc.self) == SampleDoc(name: "a"))
    }
}
