import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

private struct EdgeDoc: PersistableDocument {
    static let documentID = "edge"
    var name: String
    var values: [Int]
}

@Suite("Storage edge cases")
final class StorageEdgeCaseTests {
    let root: URL
    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ainkrad-tests-\(UUID().uuidString)")
    }
    deinit { try? FileManager.default.removeItem(at: root) }

    @Test("saving twice overwrites in place (no stale read)")
    func overwriteInPlace() {
        let store = FileDocumentStore(rootURL: root)
        store.save(EdgeDoc(name: "first", values: [1]))
        store.save(EdgeDoc(name: "second", values: [2, 3]))
        #expect(store.load(EdgeDoc.self) == EdgeDoc(name: "second", values: [2, 3]))
        // Fresh instance (no cache) reads the overwritten file.
        #expect(FileDocumentStore(rootURL: root).load(EdgeDoc.self) == EdgeDoc(name: "second", values: [2, 3]))
    }

    @Test("the store creates its directory if absent")
    func createsDirectory() {
        let nested = root.appendingPathComponent("a/b/c")
        let store = FileDocumentStore(rootURL: nested)
        store.save(EdgeDoc(name: "x", values: []))
        #expect(FileManager.default.fileExists(atPath: nested.appendingPathComponent("edge.json").path))
    }

    @Test("valid JSON with the wrong shape is quarantined")
    func wrongShapeQuarantined() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Well-formed envelope, but payload lacks required `values` and is wrong type.
        let json = #"{"schemaVersion":1,"updatedAt":"2026-07-04T00:00:00Z","payload":{"name":42}}"#
        try Data(json.utf8).write(to: root.appendingPathComponent("edge.json"))

        let store = FileDocumentStore(rootURL: root)
        #expect(store.load(EdgeDoc.self) == nil)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("edge.json").path) == false)
    }

    @Test("a large payload round-trips")
    func largePayload() {
        let store = FileDocumentStore(rootURL: root)
        let big = EdgeDoc(name: String(repeating: "z", count: 10_000), values: Array(0..<5_000))
        store.save(big)
        #expect(FileDocumentStore(rootURL: root).load(EdgeDoc.self) == big)
    }

    @Test("exporting an empty directory yields a valid, empty bundle")
    func exportEmptyDirectory() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try UserDataPorter(rootURL: root).export()
        let export = try PersistenceCoding.decoder.decode(UserDataExport.self, from: data)
        #expect(export.documents.isEmpty)
        #expect(export.exportSchemaVersion == UserDataPorter.exportSchemaVersion)
    }

    @Test("delete of an absent document is a no-op, not a crash")
    func deleteAbsentIsNoOp() {
        let store = FileDocumentStore(rootURL: root)
        store.delete(EdgeDoc.self)  // never saved
        #expect(store.load(EdgeDoc.self) == nil)
    }

    @Test("rawPayloadData returns the stored payload bytes without the document type")
    func rawPayloadRoundTrips() throws {
        let store = FileDocumentStore(rootURL: root)
        store.save(GlobalSettings())  // any existing PersistableDocument with a known documentID
        let raw = try #require(store.rawPayloadData(forID: GlobalSettings.documentID))
        // The payload decodes as the document's Codable payload (not the envelope).
        #expect((try? JSONDecoder().decode(GlobalSettings.self, from: raw)) != nil)
        #expect(store.rawPayloadData(forID: "does-not-exist") == nil)
    }
}
