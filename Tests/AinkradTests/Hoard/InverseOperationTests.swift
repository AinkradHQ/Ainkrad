import Foundation
import Testing

@testable import Ainkrad

@Suite("InverseOperation")
struct InverseOperationTests {
    private let a = URL(fileURLWithPath: "/vol/a.txt")
    private let b = URL(fileURLWithPath: "/vol/dir/a.txt")

    @Test("a move inverts to a move back")
    func moveInverts() {
        let inverse = InverseOperation.forMove(items: [MovedItem(from: a, to: b)])
        #expect(inverse.action == .moveBack([MovedItem(from: b, to: a)]))
        #expect(inverse.affectedURLs == [b])
    }

    @Test("a copy inverts to deleting the copies")
    func copyInverts() {
        let inverse = InverseOperation.forCopy(created: [b])
        #expect(inverse.action == .delete([b]))
        #expect(inverse.affectedURLs == [b])
    }

    @Test("an overwrite deletes the new file AND restores the old one")
    func overwriteInverts() {
        let trashed = TrashedItem(original: b, inTrash: URL(fileURLWithPath: "/trash/a.txt"))
        let inverse = InverseOperation.forOverwrite(created: [b], overwritten: [trashed])
        #expect(inverse.action == .composite([.delete([b]), .restoreFromTrash([trashed])]))
    }

    @Test("a cross-volume move deletes the copies and restores the trashed sources")
    func crossVolumeMoveInverts() {
        let trashed = TrashedItem(original: a, inTrash: URL(fileURLWithPath: "/trash/a.txt"))
        let inverse = InverseOperation.forCrossVolumeMove(created: [b], trashedSources: [trashed])
        #expect(inverse.action == .composite([.delete([b]), .restoreFromTrash([trashed])]))
    }

    @Test("trashing inverts to a restore")
    func trashInverts() {
        let trashed = TrashedItem(original: a, inTrash: URL(fileURLWithPath: "/trash/a.txt"))
        let inverse = InverseOperation.forTrash(items: [trashed])
        #expect(inverse.action == .restoreFromTrash([trashed]))
        #expect(inverse.affectedURLs == [a])
    }

    @Test("creating a folder inverts to deleting it")
    func createFolderInverts() {
        let inverse = InverseOperation.forCreateFolder(at: b)
        #expect(inverse.action == .delete([b]))
    }

    @Test("a rename inverts to renaming back")
    func renameInverts() {
        let inverse = InverseOperation.forRename(from: a, to: b)
        #expect(inverse.action == .moveBack([MovedItem(from: b, to: a)]))
    }

    @Test("round-trips through Codable so it survives a relaunch")
    func codable() throws {
        let trashed = TrashedItem(original: b, inTrash: URL(fileURLWithPath: "/trash/a.txt"))
        let original = InverseOperation.forOverwrite(created: [b], overwritten: [trashed])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(InverseOperation.self, from: data)
        #expect(decoded.action == original.action)
        #expect(decoded.label == original.label)
        #expect(decoded.affectedURLs == original.affectedURLs)
    }

    @Test("labels read as what the user did, for the undo affordance")
    func labels() {
        #expect(InverseOperation.forCopy(created: [b]).label == "Copy 1 item")
        #expect(InverseOperation.forCopy(created: [a, b]).label == "Copy 2 items")
        #expect(InverseOperation.forTrash(items: []).label == "Delete 0 items")
        #expect(InverseOperation.forRename(from: a, to: b).label == "Rename")
        #expect(InverseOperation.forCreateFolder(at: b).label == "New folder")
    }
}
