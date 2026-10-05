import Foundation
import Testing

@testable import Ainkrad

@Suite struct DiffReviewPresentationTests {
    @Test func sideBySidePairsDeletionsWithInsertions() {
        let diff = DiffEngine.compute(old: "a\nb\nc", new: "a\nB\nc", path: "/f", context: 2)
        let rows = DiffReviewPresentation.sideBySideRows(diff.hunks[0])
        // context 'a' + changed 'b'/'B' + context 'c'
        let changed = rows.first { $0.left?.text == "b" }
        #expect(changed?.right?.text == "B")
        // context lines mirror on both sides
        #expect(rows.contains { $0.left?.text == "a" && $0.right?.text == "a" })
    }

    @Test func contextRowHasNoTint() {
        let ctx = DiffLine(kind: .context, oldNumber: 1, newNumber: 1, text: "x")
        #expect(DiffReviewPresentation.isTinted(ctx) == false)
        #expect(DiffReviewPresentation.isTinted(DiffLine(kind: .insertion, oldNumber: nil, newNumber: 1, text: "y")))
    }
}
