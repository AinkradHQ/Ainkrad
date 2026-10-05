import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@MainActor
@Suite struct SageSessionStoreTests {
    private func makeStore(
        _ persistence: PersistenceStore = InMemoryPersistenceStore(),
        start: TimeInterval = 0
    ) -> (SageSessionStore, () -> Void) {
        var t = start
        let store = SageSessionStore(
            persistence: persistence,
            now: {
                t += 1
                return Date(timeIntervalSince1970: t)
            })
        return (store, { t += 1 })
    }

    @Test func seedsAnActiveSessionWhenEmpty() {
        let (store, _) = makeStore()
        #expect(store.sessions.count == 1)
        #expect(store.activeID == store.sessions.first?.id)
    }

    @Test func syncActiveDerivesTitleFromFirstUserMessage() {
        let (store, _) = makeStore()
        store.syncActive(messages: [AgentMessage(role: .user, text: "Refactor the parser")])
        #expect(store.sessions.first?.title == "Refactor the parser")
    }

    @Test func startNewSessionAddsAndActivatesFresh() {
        let (store, _) = makeStore()
        store.syncActive(messages: [AgentMessage(role: .user, text: "one")])
        let firstID = store.activeID
        store.startNewSession()
        #expect(store.sessions.count == 2)
        #expect(store.activeID != firstID)
        #expect(store.sessions.first(where: { $0.id == store.activeID })?.messages.isEmpty == true)
    }

    @Test func activateReturnsStoredMessages() {
        let (store, _) = makeStore()
        store.syncActive(messages: [AgentMessage(role: .user, text: "keep me")])
        let firstID = store.activeID!
        store.startNewSession()
        let restored = store.activate(firstID)
        #expect(restored.map(\.text) == ["keep me"])
        #expect(store.activeID == firstID)
    }

    @Test func deleteActiveFallsThroughToAnother() {
        let (store, _) = makeStore()
        let firstID = store.activeID!
        store.startNewSession()
        store.delete(store.activeID!)
        #expect(store.activeID == firstID)
        #expect(store.sessions.count == 1)
    }

    @Test func deletingLastSeedsFresh() {
        let (store, _) = makeStore()
        store.delete(store.activeID!)
        #expect(store.sessions.count == 1)
        #expect(store.activeID != nil)
    }

    @Test func searchFiltersByTitleAndBody() {
        let (store, _) = makeStore()
        store.syncActive(messages: [AgentMessage(role: .user, text: "parser bug")])
        store.startNewSession()
        store.syncActive(messages: [AgentMessage(role: .user, text: "css layout")])
        #expect(store.results(for: "parser").count == 1)
        #expect(store.results(for: "").count == 2)
    }

    @Test func persistsAcrossInstances() {
        let persistence = InMemoryPersistenceStore()
        let (store, _) = makeStore(persistence)
        store.syncActive(messages: [AgentMessage(role: .user, text: "survive")])
        // Transcript writes are coalesced (see `SageSessionStore.syncActive`),
        // so a relaunch is only faithfully simulated by doing what quitting does:
        // `applicationWillTerminate` calls `flush()`.
        store.flush()
        let (reopened, _) = makeStore(persistence)
        #expect(reopened.results(for: "survive").count == 1)
    }

    @Test func reopenedStoreSurfacesActiveMessagesForRestore() {
        let persistence = InMemoryPersistenceStore()
        let (store, _) = makeStore(persistence)
        store.syncActive(messages: [
            AgentMessage(role: .user, text: "restore me"),
            AgentMessage(role: .assistant, text: "ok"),
        ])
        store.flush()  // as quitting does — see the note in persistsAcrossInstances
        let (reopened, _) = makeStore(persistence)
        #expect(reopened.activeMessages.map(\.text) == ["restore me", "ok"])
    }
}
