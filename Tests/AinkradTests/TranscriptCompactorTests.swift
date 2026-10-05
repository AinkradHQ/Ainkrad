import Foundation
import Testing

@testable import Ainkrad

@Suite("TranscriptCompactor")
struct TranscriptCompactorTests {
    private func convo(_ n: Int) -> [AgentMessage] {
        (0..<n).map { AgentMessage(role: $0 % 2 == 0 ? .user : .assistant, text: "msg \($0)") }
    }

    @Test func keepsRecentTailAndInsertsSummary() {
        let out = TranscriptCompactor.compact(convo(20), keepRecent: 4, summary: "did stuff")
        #expect(out.count == 5)  // 1 summary + 4 recent
        #expect(out.first?.text.contains("summarized") == true)
        #expect(out.last?.text == "msg 19")
    }

    @Test func shortConvoUnchanged() {
        let short = convo(3)
        let out = TranscriptCompactor.compact(short, keepRecent: 6, summary: "x")
        #expect(out == short)
    }

    @Test func heuristicSummaryCaps() {
        let s = TranscriptCompactor.summarizeHeuristically(convo(100), maxChars: 50)
        #expect(s.count <= 50)
    }
}
