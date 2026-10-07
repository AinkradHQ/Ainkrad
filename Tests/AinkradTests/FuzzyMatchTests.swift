import Testing

@testable import Ainkrad

@Suite("fuzzyMatches")
struct FuzzyMatchTests {

    @Test("empty query matches anything")
    func emptyQueryMatchesAnything() {
        #expect(fuzzyMatches(query: "", target: "Terminal"))
    }

    @Test("exact match matches")
    func exactMatchMatches() {
        #expect(fuzzyMatches(query: "Terminal", target: "Terminal"))
    }

    @Test("in-order subsequence matches")
    func inOrderSubsequenceMatches() {
        #expect(fuzzyMatches(query: "trm", target: "Terminal"))
    }

    @Test("match is case-insensitive")
    func matchIsCaseInsensitive() {
        #expect(fuzzyMatches(query: "TERM", target: "Terminal"))
    }

    @Test("characters not present do not match")
    func charactersNotPresentDoNotMatch() {
        #expect(!fuzzyMatches(query: "xyz", target: "Terminal"))
    }

    @Test("out-of-order characters do not match")
    func outOfOrderCharactersDoNotMatch() {
        #expect(!fuzzyMatches(query: "art", target: "Terminal"))
    }
}
