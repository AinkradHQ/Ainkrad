import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@MainActor
@Suite("SessionShareStore")
struct SessionShareStoreTests {
    private func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    @Test func writesSelfContainedHtmlAndRecordsMetadata() throws {
        let dir = tempDir()
        let persistence = InMemoryPersistenceStore()
        let store = SessionShareStore(
            persistence: persistence, baseDirectory: dir, now: { Date(timeIntervalSince1970: 0) })
        let messages = [AgentMessage(role: .user, text: "hi with sk-live-XYZ")]
        let record = try store.share(messages: messages, title: "Chat", redactions: ["sk-live-XYZ"])

        #expect(FileManager.default.fileExists(atPath: record.fileURL.path))
        let html = try String(contentsOf: record.fileURL, encoding: .utf8)
        #expect(html.hasPrefix("<!doctype html>"))
        #expect(!html.contains("sk-live-XYZ"))
        #expect(store.shares.contains { $0.id == record.id })
        // persisted across a fresh store instance
        let reopened = SessionShareStore(persistence: persistence, baseDirectory: dir)
        #expect(reopened.shares.contains { $0.id == record.id })
    }

    @Test func recordPathSurvivesBaseDirectoryMove() throws {
        // The artifact path must be reconstructed from the CURRENT base directory
        // + id on load, so a persisted (stale) absolute path is never trusted.
        let persistence = InMemoryPersistenceStore()
        let originalBase = tempDir()
        let store = SessionShareStore(persistence: persistence, baseDirectory: originalBase)
        let record = try store.share(messages: [AgentMessage(role: .user, text: "x")], title: "T", redactions: [])

        // Simulate the whole Shares dir relocating (e.g. bundle rename) by moving it.
        let movedBase = tempDir()
        let movedShareDir = movedBase.appendingPathComponent(record.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: movedBase, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: movedShareDir)
        try FileManager.default.moveItem(
            at: originalBase.appendingPathComponent(record.id.uuidString, isDirectory: true),
            to: movedShareDir)

        // Reopen against the NEW base — the record's fileURL must resolve to the moved file.
        let reopened = SessionShareStore(persistence: persistence, baseDirectory: movedBase)
        let reloaded = try #require(reopened.shares.first { $0.id == record.id })
        #expect(reloaded.fileURL.path.hasPrefix(movedBase.path))
        #expect(FileManager.default.fileExists(atPath: reloaded.fileURL.path))
    }

    @Test func deleteRemovesRecordAndFile() throws {
        let dir = tempDir()
        let store = SessionShareStore(persistence: InMemoryPersistenceStore(), baseDirectory: dir)
        let record = try store.share(messages: [AgentMessage(role: .user, text: "x")], title: "T", redactions: [])
        store.delete(record.id)
        #expect(store.shares.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: record.fileURL.path))
    }
}
