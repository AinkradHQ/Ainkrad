import AinkradHostRuntime
import Foundation
import AinkradAppKit
import Testing

@testable import Ainkrad

@Suite("AgentSessionPartialApproval")
@MainActor
struct AgentSessionPartialApprovalTests {
    @Test func reconstructionRewritesInputForPartialAccept() {
        // Pure check of the seam helper the session uses so we avoid a full loop.
        let original = (1...20).map { "l\($0)" }.joined(separator: "\n")
        var arr = (1...20).map { "l\($0)" }
        arr[1] = "l2X"
        arr[18] = "l19X"
        let updated = arr.joined(separator: "\n")
        let fileDiff = AinkradDiffEngine.compute(old: original, new: updated, path: "/f.txt", context: 2)

        let rewritten = AgentSession.rewriteEditForPartialApproval(
            input: .object([
                "path": .string("/f.txt"),
                "old_string": .string("ignored"),
                "new_string": .string("ignored"),
            ]),
            fileDiff: fileDiff, rejecting: [1])

        var expected = (1...20).map { "l\($0)" }
        expected[1] = "l2X"
        #expect(rewritten["old_string"]?.stringValue == original)
        #expect(rewritten["new_string"]?.stringValue == expected.joined(separator: "\n"))
    }

    @Test func emptyRejectionLeavesInputUnchanged() {
        let fileDiff = AinkradDiffEngine.compute(old: "a\nb", new: "a\nB", path: "/f", context: 2)
        let input = JSONValue.object([
            "path": .string("/f"),
            "old_string": .string("b"), "new_string": .string("B"),
        ])
        let rewritten = AgentSession.rewriteEditForPartialApproval(input: input, fileDiff: fileDiff, rejecting: [])
        #expect(rewritten == input)  // no subset rejected → original find/replace untouched
    }
}
