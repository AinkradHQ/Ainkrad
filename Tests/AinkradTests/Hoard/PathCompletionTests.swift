import Foundation
import Testing

@testable import Ainkrad

@Suite("Path completion")
struct PathCompletionTests {
    private let home = URL(fileURLWithPath: "/Users/test")

    private func makeFS() -> InMemoryFileSystem {
        let fs = InMemoryFileSystem(home: home)
        fs.add(directory: "/Users/test", children: ["Documents/", "Downloads/", "Desktop/", "notes.txt"])
        fs.add(directory: "/Users/test/Documents", children: ["report.pdf"])
        return fs
    }

    @Test("expands a leading tilde")
    func expandsTilde() {
        #expect(expandTilde("~/Documents", home: home) == "/Users/test/Documents")
        #expect(expandTilde("~", home: home) == "/Users/test")
    }

    @Test("leaves absolute paths alone")
    func leavesAbsolute() {
        #expect(expandTilde("/usr/local", home: home) == "/usr/local")
    }

    @Test("does not expand a tilde mid-path")
    func onlyLeadingTilde() {
        #expect(expandTilde("/tmp/~backup", home: home) == "/tmp/~backup")
    }

    @Test("completes a unique prefix")
    func uniquePrefix() {
        #expect(completePath("/Users/test/Doc", using: makeFS(), home: home) == "/Users/test/Documents")
    }

    @Test("completes to the longest common prefix when ambiguous")
    func ambiguousPrefix() {
        // "Do" matches Documents and Downloads → common prefix "Do".
        #expect(completePath("/Users/test/Do", using: makeFS(), home: home) == "/Users/test/Do")
    }

    @Test("returns nil when nothing matches")
    func noMatch() {
        #expect(completePath("/Users/test/zzz", using: makeFS(), home: home) == nil)
    }

    @Test("completes through a tilde")
    func completesThroughTilde() {
        #expect(completePath("~/Doc", using: makeFS(), home: home) == "/Users/test/Documents")
    }

    @Test("returns nil for an unreadable parent directory")
    func unreadableParent() {
        #expect(completePath("/nope/xyz", using: makeFS(), home: home) == nil)
    }

    @Test("completion is case-insensitive")
    func caseInsensitive() {
        #expect(completePath("/Users/test/doc", using: makeFS(), home: home) == "/Users/test/Documents")
    }
}
