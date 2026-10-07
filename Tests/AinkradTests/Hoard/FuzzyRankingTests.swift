import Foundation
import Testing

@testable import Ainkrad

@Suite("Fuzzy ranking")
struct FuzzyRankingTests {
    @Test("matches a subsequence")
    func matchesSubsequence() {
        #expect(fuzzyScore("FileListView.swift", pattern: "flv") != nil)
        #expect(fuzzyScore("main.swift", pattern: "msw") != nil)
    }

    @Test("rejects characters that are not present in order")
    func rejectsOutOfOrder() {
        #expect(fuzzyScore("main.swift", pattern: "wsm") == nil)
        #expect(fuzzyScore("main.swift", pattern: "xyz") == nil)
    }

    @Test("a pattern longer than the candidate cannot match")
    func rejectsTooLong() {
        #expect(fuzzyScore("ab", pattern: "abc") == nil)
    }

    @Test("an empty pattern matches everything with no highlights")
    func emptyPattern() {
        #expect(fuzzyScore("anything", pattern: "")?.matchedIndices == [])
    }

    @Test("reports matched indices for highlighting")
    func reportsIndices() {
        #expect(fuzzyScore("abc", pattern: "ac")?.matchedIndices == [0, 2])
    }

    @Test("matching is case-insensitive")
    func caseInsensitive() {
        #expect(fuzzyScore("FileListView", pattern: "FLV") != nil)
        #expect(fuzzyScore("filelistview", pattern: "FLV") != nil)
    }

    // MARK: - Scoring

    @Test("a prefix match outranks a mid-word match")
    func prefixWins() {
        let prefix = fuzzyScore("main.swift", pattern: "main")!
        let middle = fuzzyScore("domain.swift", pattern: "main")!
        #expect(prefix.score > middle.score)
    }

    @Test("word starts outrank scattered letters")
    func wordStartsWin() {
        let wordStarts = fuzzyScore("file-list-view.swift", pattern: "flv")!
        let scattered = fuzzyScore("aflavour.swift", pattern: "flv")!
        #expect(wordStarts.score > scattered.score)
    }

    @Test("camelCase humps count as word starts")
    func camelCaseHumps() {
        #expect(
            fuzzyScore("FileListView", pattern: "flv")!.score
                > fuzzyScore("fffllvvv", pattern: "flv")!.score)
    }

    @Test("consecutive runs beat gaps")
    func consecutiveWins() {
        let consecutive = fuzzyScore("abcdef", pattern: "abc")!
        let gapped = fuzzyScore("axbxcx", pattern: "abc")!
        #expect(consecutive.score > gapped.score)
    }

    @Test("shorter candidates win ties")
    func shorterWinsTies() {
        let short = fuzzyScore("main.swift", pattern: "main")!
        let long = fuzzyScore("main-configuration-loader-extended.swift", pattern: "main")!
        #expect(short.score > long.score)
    }

    // MARK: - Ranking

    @Test("ranking returns best first and drops non-matches")
    func ranking() {
        let candidates = ["domain.swift", "main.swift", "unrelated.txt", "FileListView.swift"]
        let ranked = fuzzyRank(candidates, pattern: "main") { $0 }
        #expect(ranked.first?.item == "main.swift")
        #expect(!ranked.contains { $0.item == "unrelated.txt" })
        #expect(!ranked.contains { $0.item == "FileListView.swift" })
    }

    @Test("an empty pattern ranks everything, unchanged")
    func rankingEmptyPattern() {
        let candidates = ["a", "b", "c"]
        #expect(fuzzyRank(candidates, pattern: "") { $0 }.map(\.item) == candidates)
    }

    // Results jittering as you type is the classic fuzzy-finder annoyance.
    @Test("equal scores keep a stable order")
    func stableOrdering() {
        let candidates = ["aa1.txt", "aa2.txt", "aa3.txt"]
        let ranked = fuzzyRank(candidates, pattern: "aa") { $0 }
        #expect(ranked.map(\.item) == candidates)
    }
}
