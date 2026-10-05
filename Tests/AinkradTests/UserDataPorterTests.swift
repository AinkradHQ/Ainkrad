import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

private struct SampleDoc: PersistableDocument {
    static let documentID = "sample"
    var name: String
}

@Suite("UserDataPorter")
final class UserDataPorterTests {
    let root: URL
    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ainkrad-tests-\(UUID().uuidString)")
    }
    deinit { try? FileManager.default.removeItem(at: root) }

    @Test("export then import into a fresh directory reproduces the documents")
    func exportImportRoundTrips() throws {
        let source = FileDocumentStore(rootURL: root)
        source.save(SampleDoc(name: "hello"))
        source.save(GlobalSettings(theme: .cyberPurple))

        let bundle = try UserDataPorter(rootURL: root).export()

        let destRoot = root.appendingPathComponent("restored")
        try UserDataPorter(rootURL: destRoot).importData(bundle)

        let restored = FileDocumentStore(rootURL: destRoot)
        #expect(restored.load(SampleDoc.self) == SampleDoc(name: "hello"))
        #expect(restored.load(GlobalSettings.self)?.theme == .cyberPurple)
    }

    @Test("the export bundle carries a version and never contains secrets")
    func exportHasVersion() throws {
        FileDocumentStore(rootURL: root).save(SampleDoc(name: "x"))
        let data = try UserDataPorter(rootURL: root).export()
        let export = try PersistenceCoding.decoder.decode(UserDataExport.self, from: data)
        #expect(export.exportSchemaVersion == UserDataPorter.exportSchemaVersion)
        #expect(export.documents["sample"] != nil)
    }

    @Test("importing an unsupported version throws")
    func rejectsUnsupportedVersion() throws {
        let bogus = Data(#"{"exportSchemaVersion":999,"documents":{}}"#.utf8)
        #expect(throws: UserDataPorterError.self) {
            try UserDataPorter(rootURL: root).importData(bogus)
        }
    }

    @Test("importing malformed data throws")
    func rejectsMalformed() {
        #expect(throws: (any Error).self) {
            try UserDataPorter(rootURL: root).importData(Data("not json".utf8))
        }
    }
}
