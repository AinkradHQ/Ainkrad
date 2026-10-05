import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite struct SageSessionsDocumentTests {
    @Test func roundTripsThroughPersistence() throws {
        let store = InMemoryPersistenceStore()
        let fixed = Date(timeIntervalSince1970: 1_000)
        let session = SavedSession(
            id: UUID(), title: "Hi", createdAt: fixed,
            updatedAt: fixed, messages: [AgentMessage(role: .user, text: "hi")])
        store.save(SageSessionsDocument(sessions: [session], activeID: session.id))
        let loaded = store.load(SageSessionsDocument.self)
        #expect(loaded?.sessions == [session])
        #expect(loaded?.activeID == session.id)
    }

    @Test func defaultsMissingFields() {
        let doc = SageSessionsDocument()
        #expect(doc.sessions.isEmpty)
        #expect(doc.activeID == nil)
    }
}
