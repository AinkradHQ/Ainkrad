import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

private struct SampleDoc: PersistableDocument {
    static let documentID = "sample"
    var name: String
    var count: Int
}

@Suite("FileDocumentStore")
final class FileDocumentStoreTests {
    let root: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ainkrad-tests-\(UUID().uuidString)")
    }
    deinit { try? FileManager.default.removeItem(at: root) }

    @Test("load returns nil for an absent document")
    func loadNilWhenAbsent() {
        let store = FileDocumentStore(rootURL: root)
        #expect(store.load(SampleDoc.self) == nil)
    }

    @Test("save then load round-trips the document")
    func saveThenLoad() {
        let store = FileDocumentStore(rootURL: root)
        store.save(SampleDoc(name: "a", count: 3))
        #expect(store.load(SampleDoc.self) == SampleDoc(name: "a", count: 3))
    }

    @Test("a saved document survives a fresh store instance (relaunch)")
    func survivesRelaunch() {
        FileDocumentStore(rootURL: root).save(SampleDoc(name: "b", count: 7))
        #expect(FileDocumentStore(rootURL: root).load(SampleDoc.self) == SampleDoc(name: "b", count: 7))
    }

    @Test("on-disk file uses the versioned envelope")
    func writesVersionedEnvelope() throws {
        FileDocumentStore(rootURL: root).save(SampleDoc(name: "c", count: 1))
        let url = root.appendingPathComponent("sample.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        #expect(object?["schemaVersion"] as? Int == 1)
        #expect(object?["updatedAt"] != nil)
        #expect((object?["payload"] as? [String: Any])?["name"] as? String == "c")
    }

    @Test("delete removes the document and its file")
    func deleteRemoves() {
        let store = FileDocumentStore(rootURL: root)
        store.save(SampleDoc(name: "a", count: 3))
        store.delete(SampleDoc.self)
        #expect(store.load(SampleDoc.self) == nil)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("sample.json").path) == false)
    }

    @Test("a corrupt file is quarantined and load returns nil")
    func quarantinesCorruptFile() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("sample.json")
        try Data("{ not valid json".utf8).write(to: url)

        let store = FileDocumentStore(rootURL: root)
        #expect(store.load(SampleDoc.self) == nil)
        #expect(FileManager.default.fileExists(atPath: url.path) == false)
        let quarantined = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasPrefix("sample.json.corrupt-") }
        #expect(quarantined.count == 1)
    }
}
