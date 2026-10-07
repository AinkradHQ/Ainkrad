import Foundation
import Testing

@testable import Ainkrad

@Suite("Type-to-select")
struct TypeAheadTests {
    private let names = ["apple.txt", "Banana.md", "apricot.png", "cherry.txt"]

    @Test("matches on prefix, case-insensitively")
    func matchesPrefix() {
        #expect(typeAheadIndex(in: names, matching: "ban", from: 0) == 1)
        #expect(typeAheadIndex(in: names, matching: "BAN", from: 0) == 1)
    }

    // Prefix, not fuzzy — "/" and ⌘P own fuzzy search. Someone typing "re"
    // expects "readme", not the best-scoring name containing an r and an e.
    @Test("does not match a substring in the middle of a name")
    func noSubstringMatch() {
        #expect(typeAheadIndex(in: names, matching: "nana", from: 0) == nil)
    }

    @Test("search wraps around the end of the listing")
    func wraps() {
        // Starting past the last entry still finds the first match.
        #expect(typeAheadIndex(in: names, matching: "apple", from: 3) == 0)
    }

    @Test("an empty query or empty listing matches nothing")
    func emptyInputs() {
        #expect(typeAheadIndex(in: names, matching: "", from: 0) == nil)
        #expect(typeAheadIndex(in: [], matching: "a", from: 0) == nil)
    }

    @Test("consecutive letters build up a prefix")
    func buildsPrefix() {
        var buffer = TypeAheadBuffer()
        let now = Date()
        #expect(buffer.append("a", at: now) == .search("a"))
        #expect(buffer.append("p", at: now.addingTimeInterval(0.1)) == .search("ap"))
        #expect(buffer.append("r", at: now.addingTimeInterval(0.2)) == .search("apr"))
    }

    @Test("a pause starts a new word")
    func timeoutResets() {
        var buffer = TypeAheadBuffer()
        let now = Date()
        _ = buffer.append("a", at: now)
        #expect(buffer.append("b", at: now.addingTimeInterval(2)) == .search("b"))
    }

    // The behaviour that makes type-ahead usable in a folder of twelve
    // `image-*.png`: pressing the same letter cycles rather than searching for
    // a doubled letter.
    @Test("repeating one letter asks for the next match, not a doubled prefix")
    func repeatedLetterCycles() {
        var buffer = TypeAheadBuffer()
        let now = Date()
        #expect(buffer.append("a", at: now) == .search("a"))
        #expect(buffer.append("a", at: now.addingTimeInterval(0.1)) == .nextMatch("a"))
        // And keeps cycling — the query must NOT have grown to "aa".
        #expect(buffer.append("a", at: now.addingTimeInterval(0.2)) == .nextMatch("a"))
    }
}
