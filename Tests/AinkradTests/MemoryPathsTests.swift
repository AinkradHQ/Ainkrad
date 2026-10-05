import Foundation
import Testing

@testable import Ainkrad

@Suite("MemoryPaths")
struct MemoryPathsTests {
    @Test func mapsEachFileToRoot() {
        let root = URL(fileURLWithPath: "/tmp/mem-\(UUID().uuidString)")
        let p = MemoryPaths(root: root)
        #expect(p.url(for: .user).lastPathComponent == "USER.md")
        #expect(p.url(for: .memory).lastPathComponent == "MEMORY.md")
        #expect(p.url(for: .agents).lastPathComponent == "AGENTS.md")
        #expect(p.indexURL.lastPathComponent == "index.sqlite")
        #expect(p.profileURL.lastPathComponent == "profile.json")
        #expect(p.sessionsDir.lastPathComponent == "sessions")
        #expect(p.sessionURL(id: "abc").lastPathComponent == "abc.md")
    }
}
