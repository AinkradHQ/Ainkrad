import Foundation
import Testing

@testable import Ainkrad

@Suite("MemoryIndex")
struct MemoryIndexTests {
    private func index() throws -> (MemoryIndex, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("memidx-\(UUID().uuidString).sqlite")
        return (try MemoryIndex(url: url), url)
    }

    @Test func indexesAndFinds() throws {
        let (idx, url) = try index()
        defer { try? FileManager.default.removeItem(at: url) }
        idx.upsert(source: "MEMORY.md", title: "Memory", body: "the user prefers tabs over spaces")
        let hits = idx.search("tabs")
        #expect(hits.count == 1)
        #expect(hits.first?.source == "MEMORY.md")
    }

    @Test func upsertReplacesPriorRowsForSource() throws {
        let (idx, url) = try index()
        defer { try? FileManager.default.removeItem(at: url) }
        idx.upsert(source: "MEMORY.md", title: "Memory", body: "likes tabs")
        idx.upsert(source: "MEMORY.md", title: "Memory", body: "likes spaces")
        #expect(idx.search("tabs").isEmpty)
        #expect(idx.search("spaces").count == 1)
    }

    @Test func clearEmptiesIndex() throws {
        let (idx, url) = try index()
        defer { try? FileManager.default.removeItem(at: url) }
        idx.upsert(source: "s", title: "t", body: "findme")
        idx.clear()
        #expect(idx.search("findme").isEmpty)
    }

    @Test func throwsWhenOpenTargetIsADirectory() throws {
        // sqlite3_open cannot open a path that is itself an existing directory; this
        // reliably forces SQLITE_CANTOPEN without depending on filesystem permissions.
        let dirURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("memidx-dir-\(UUID().uuidString).sqlite")
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dirURL) }
        #expect(throws: MemoryIndexError.self) { try MemoryIndex(url: dirURL) }
    }

    @Test func survivesReopen() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("memidx-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        try MemoryIndex(url: url).upsert(source: "s", title: "t", body: "persistent fact")
        #expect(try MemoryIndex(url: url).search("persistent").count == 1)
    }
}
