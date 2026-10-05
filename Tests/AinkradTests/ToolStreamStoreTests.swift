import Testing

@testable import Ainkrad

@Suite("ToolStreamStore")
@MainActor
struct ToolStreamStoreTests {
    @Test func appendKeepsLongestSnapshotForActiveCall() {
        let store = ToolStreamStore()
        store.begin("t1")
        store.appendActive("line 1\n")
        store.appendActive("line 1\nline 2\n")
        #expect(store.liveOutput(for: "t1") == "line 1\nline 2\n")
        // An out-of-order shorter snapshot must not shrink the buffer.
        store.appendActive("line 1\n")
        #expect(store.liveOutput(for: "t1") == "line 1\nline 2\n")
    }

    @Test func finishWritesAuthoritativeOutputAndClearsActive() {
        let store = ToolStreamStore()
        store.begin("t1")
        store.appendActive("partial")
        store.finish("t1", finalOutput: "partial-final")
        #expect(store.liveOutput(for: "t1") == "partial-final")
        // A stray append after finish (no active call) is ignored.
        store.appendActive("late")
        #expect(store.liveOutput(for: "t1") == "partial-final")
    }

    @Test func unknownCallHasNoLiveOutput() {
        let store = ToolStreamStore()
        #expect(store.liveOutput(for: "nope") == nil)
    }

    @Test func idCheckedAppendIsNoOpWhenIDNotActive() {
        let store = ToolStreamStore()
        store.begin("a")
        // A stale snapshot bound to "b" while "a" is active must not land anywhere.
        store.appendActive("x", for: "b")
        #expect(store.liveOutput(for: "a") == "")
        #expect(store.liveOutput(for: "b") == nil)
    }

    @Test func idCheckedAppendAppliesWhenIDMatchesActive() {
        let store = ToolStreamStore()
        store.begin("a")
        store.appendActive("line 1\n", for: "a")
        #expect(store.liveOutput(for: "a") == "line 1\n")
        // Simulate a successor call taking over `active`; the stale id no
        // longer matches and the append is dropped, protecting call "b"'s buffer.
        store.finish("a", finalOutput: "line 1\n")
        store.begin("b")
        store.appendActive("stale from a\n", for: "a")
        #expect(store.liveOutput(for: "b") == "")
    }
}
