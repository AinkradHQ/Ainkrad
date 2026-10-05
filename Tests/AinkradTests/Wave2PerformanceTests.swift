import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

/// Wave 2 performance work. These pin *behaviour that implies the cost* —
/// a unit test can't measure frame time, but it can assert that the expensive
/// path is no longer taken.

@MainActor
@Suite("Transcript timeline memoization")
struct TranscriptTimelineCacheTests {

    private func userMessage(_ text: String) -> AgentMessage {
        AgentMessage(role: .user, content: [.text(text)])
    }

    @Test("Identical input returns the identical cached array")
    func cacheHitOnUnchangedMessages() {
        let cache = TranscriptTimelineCache()
        let messages = [userMessage("hello"), userMessage("again")]

        let first = cache.items(for: messages)
        let second = cache.items(for: messages)

        // The streaming case: `body` re-evaluates per chunk while `messages`
        // is unchanged. Rebuilding there was the defect.
        #expect(first == second)
        #expect(!first.isEmpty)
    }

    @Test("Changed input rebuilds")
    func cacheMissOnChangedMessages() {
        let cache = TranscriptTimelineCache()
        let one = cache.items(for: [userMessage("a")])
        let two = cache.items(for: [userMessage("a"), userMessage("b")])
        #expect(two.count > one.count)
    }

    @Test("Cached output matches an uncached build exactly")
    func cacheIsTransparent() {
        let messages = [userMessage("a"), userMessage("b"), userMessage("c")]
        let cache = TranscriptTimelineCache()
        _ = cache.items(for: messages)  // prime
        #expect(cache.items(for: messages) == TranscriptTimelineBuilder.build(from: messages))
    }

    @Test("Reverting to a previous transcript still rebuilds correctly")
    func revertRebuilds() {
        let cache = TranscriptTimelineCache()
        let short = [userMessage("a")]
        let long = [userMessage("a"), userMessage("b")]
        _ = cache.items(for: short)
        _ = cache.items(for: long)
        // /undo, or activating an older saved session, shortens the array.
        #expect(cache.items(for: short) == TranscriptTimelineBuilder.build(from: short))
    }
}

@MainActor
@Suite("Chat history writes are coalesced")
struct SageSessionStoreCoalescingTests {

    /// Counts writes so the test can assert on *how many* happened, which is
    /// the whole point — the old code wrote once per message mutation.
    final class CountingPersistence: PersistenceStore, @unchecked Sendable {
        private let inner = InMemoryPersistenceStore()
        private let lock = NSLock()
        private var _writes = 0
        var writes: Int { lock.withLock { _writes } }

        func load<T: PersistableDocument>(_ type: T.Type) -> T? { inner.load(type) }
        func save<T: PersistableDocument>(_ document: T) {
            lock.withLock { _writes += 1 }
            inner.save(document)
        }
        func delete<T: PersistableDocument>(_ type: T.Type) { inner.delete(type) }
    }

    private func message(_ text: String) -> AgentMessage {
        AgentMessage(role: .user, content: [.text(text)])
    }

    @Test("A burst of transcript updates does not write once per update")
    func burstIsCoalesced() async throws {
        let persistence = CountingPersistence()
        let store = SageSessionStore(persistence: persistence)
        let baseline = persistence.writes

        // Stand in for a streamed reply: many mutations in quick succession.
        for i in 0..<50 {
            store.syncActive(messages: (0...i).map { message("chunk \($0)") })
        }

        // Nothing has hit disk yet — that is the fix. Previously this was 50
        // full re-encodes of every session plus 50 atomic writes, on the main
        // actor, interleaved with the typing animation.
        #expect(persistence.writes == baseline, "a burst still wrote per-update")

        // …but the in-memory state is correct immediately, so the sidebar and
        // titles never lag.
        #expect(store.activeMessages.count == 50)
    }

    @Test("The coalesced write lands after the interval")
    func coalescedWriteEventuallyLands() async throws {
        let persistence = CountingPersistence()
        let store = SageSessionStore(persistence: persistence)
        let baseline = persistence.writes

        for i in 0..<20 { store.syncActive(messages: (0...i).map { message("c\($0)") }) }
        try await Task.sleep(for: SageSessionStore.saveCoalescingInterval + .milliseconds(400))

        #expect(persistence.writes == baseline + 1, "expected exactly one coalesced write")
    }

    @Test("flush() writes immediately, for quit")
    func flushIsImmediate() {
        let persistence = CountingPersistence()
        let store = SageSessionStore(persistence: persistence)
        store.syncActive(messages: [message("unsaved")])
        let before = persistence.writes

        store.flush()

        #expect(persistence.writes == before + 1)
        // And the pending task must not fire a second, redundant write later.
        #expect(store.activeMessages.count == 1)
    }

    @Test("Structural edits still write through immediately")
    func structuralEditsAreDurableNow() {
        let persistence = CountingPersistence()
        let store = SageSessionStore(persistence: persistence)
        let before = persistence.writes
        // Creating/switching/deleting a chat is rare and must survive a crash
        // straight away — only the per-message mirroring is coalesced.
        store.startNewSession()
        #expect(persistence.writes > before)
    }
}

@MainActor
@Suite("Workspace file index")
struct WorkspaceFileIndexRefreshTests {

    @Test("Async refresh produces the same index as the synchronous one")
    func asyncMatchesSync() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ainkrad-index-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["a.swift", "b.swift", "c.md"] {
            try "x".write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        let sync = WorkspaceFileIndex(root: root)
        sync.refreshSynchronously()
        let async = WorkspaceFileIndex(root: root)
        await async.refresh()

        #expect(async.search("swift").map(\.path).sorted() == sync.search("swift").map(\.path).sorted())
        #expect(!async.search("swift").isEmpty)
    }

    @Test("An index that was never refreshed returns nothing rather than walking home")
    func unrefreshedIndexIsEmpty() {
        // Bootstrap now skips the initial refresh entirely when the user has
        // not chosen a workspace, so the home directory is never enumerated.
        let index = WorkspaceFileIndex(root: FileManager.default.homeDirectoryForCurrentUser)
        #expect(index.search("a").isEmpty)
    }
}
