import Foundation
import Testing

@testable import Ainkrad

@Suite("MemoryStore")
@MainActor
struct MemoryStoreTests {
    private func store() -> (MemoryStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mem-\(UUID().uuidString)")
        return (MemoryStore(paths: MemoryPaths(root: root)), root)
    }

    @Test func readsEmptyWhenAbsent() {
        let (s, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(s.read(.memory) == "")
    }

    @Test func writeThenReadRoundTrips() {
        let (s, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        s.write("hello", to: .user)
        #expect(s.read(.user) == "hello")
    }

    @Test func appendAddsNewlineSeparation() {
        let (s, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        s.append("a", to: .memory)
        s.append("b", to: .memory)
        #expect(s.read(.memory) == "a\nb")
    }

    @Test func alwaysLoadedSetSkipsEmptyFiles() {
        let (s, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        s.write("who I am", to: .user)
        let set = s.alwaysLoadedSet()
        #expect(set.count == 1)
        #expect(set.first?.0 == .user)
    }

    @Test func alwaysLoadedSetTailCaps() {
        let (s, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        s.write(String(repeating: "x", count: 10_000), to: .memory)
        let text = s.alwaysLoadedSet(perFileCharCap: 100).first!.1
        #expect(text.count <= 100)
    }

    @Test func onChangeFires() {
        let (s, root) = store()
        defer { try? FileManager.default.removeItem(at: root) }
        var changed: MemoryFile?
        s.onChange = { changed = $0 }
        s.write("x", to: .agents)
        #expect(changed == .agents)
    }
}
