import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@MainActor
@Suite("SessionShareCoordinator")
struct SessionShareCoordinatorTests {
    @Test func sharesAndReturnsFileLink() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SessionShareStore(persistence: InMemoryPersistenceStore(), baseDirectory: dir)
        let coordinator = SessionShareCoordinator(store: store)
        let out = try coordinator.shareCurrentSession(
            messages: [AgentMessage(role: .user, text: "hi sk-live-XYZ")],
            title: "Chat",
            redactionsText: "sk-live-XYZ")
        #expect(out.clipboardLink.hasPrefix("file://"))
        #expect(out.clipboardLink.contains(out.record.id.uuidString))
        let html = try String(contentsOf: out.record.fileURL, encoding: .utf8)
        #expect(!html.contains("sk-live-XYZ"))
    }
}
