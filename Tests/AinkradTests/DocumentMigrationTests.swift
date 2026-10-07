import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

/// v2 renamed the field `title` -> `name`. The migrator maps the old key.
private struct MigratableDoc: PersistableDocument {
    static let documentID = "migratable"
    static var currentSchemaVersion: Int { 2 }
    static var migrators: [DocumentMigrator] {
        [
            DocumentMigrator(from: 1) { payload in
                guard case .object(var fields) = payload else { return payload }
                if let title = fields["title"] {
                    fields["name"] = title
                    fields["title"] = nil
                }
                return .object(fields)
            }
        ]
    }
    var name: String
}

@Suite("Document migration")
final class DocumentMigrationTests {
    let root: URL
    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ainkrad-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }

    private func writeEnvelope(version: Int, payloadJSON: String) throws {
        let json = #"{"schemaVersion":\#(version),"updatedAt":"2026-07-04T00:00:00Z","payload":\#(payloadJSON)}"#
        try Data(json.utf8).write(to: root.appendingPathComponent("migratable.json"))
    }

    @Test("a v1 payload is migrated to v2 on load")
    func migratesV1ToV2() throws {
        try writeEnvelope(version: 1, payloadJSON: #"{"title":"hello"}"#)
        let store = FileDocumentStore(rootURL: root)
        #expect(store.load(MigratableDoc.self) == MigratableDoc(name: "hello"))
    }

    @Test("a migrated document is re-saved at the current version")
    func reSavesAtCurrentVersion() throws {
        try writeEnvelope(version: 1, payloadJSON: #"{"title":"hi"}"#)
        _ = FileDocumentStore(rootURL: root).load(MigratableDoc.self)

        let object =
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: root.appendingPathComponent("migratable.json"))) as? [String: Any]
        #expect(object?["schemaVersion"] as? Int == 2)
    }

    @Test("a stored version newer than the current build is quarantined")
    func newerThanBuildQuarantines() throws {
        // Stored at version 5 with no migrator path to 2.
        try writeEnvelope(version: 5, payloadJSON: #"{"name":"x"}"#)
        let store = FileDocumentStore(rootURL: root)
        #expect(store.load(MigratableDoc.self) == nil)
        #expect(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("migratable.json").path) == false)
    }

    @Test("a payload with no migrator for its version is quarantined")
    func missingMigratorForVersionQuarantines() throws {
        // Stored at version 0: the loop is entered (0 < 2), but there is no
        // migrator registered for fromVersion 0 (only from: 1 exists).
        try writeEnvelope(version: 0, payloadJSON: #"{"name":"x"}"#)
        let store = FileDocumentStore(rootURL: root)
        #expect(store.load(MigratableDoc.self) == nil)
        #expect(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("migratable.json").path) == false)
        let quarantined = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .contains { $0.hasPrefix("migratable.json.corrupt-") }
        #expect(quarantined)
    }
}
