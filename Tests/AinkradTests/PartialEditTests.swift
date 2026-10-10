import Foundation
import AinkradAppKit
import Testing

@testable import Ainkrad

@Suite struct PartialEditTests {
    private func diff(_ old: String, _ new: String) -> AinkradFileDiff {
        AinkradDiffEngine.compute(old: old, new: new, path: "/f", context: 2)
    }

    @Test func rejectingNoneYieldsFullUpdate() {
        let old = (1...20).map { "l\($0)" }.joined(separator: "\n")
        var arr = (1...20).map { "l\($0)" }
        arr[1] = "l2X"
        arr[18] = "l19X"
        let new = arr.joined(separator: "\n")
        #expect(PartialEdit.reconstruct(diff(old, new), rejecting: []) == new)
    }

    @Test func rejectingAllYieldsOriginal() {
        let old = (1...20).map { "l\($0)" }.joined(separator: "\n")
        var arr = (1...20).map { "l\($0)" }
        arr[1] = "l2X"
        arr[18] = "l19X"
        let d = diff(old, arr.joined(separator: "\n"))
        #expect(PartialEdit.reconstruct(d, rejecting: Set(d.hunks.map(\.id))) == old)
    }

    @Test func rejectingSecondHunkKeepsFirstEditOnly() {
        let old = (1...20).map { "l\($0)" }.joined(separator: "\n")
        var arr = (1...20).map { "l\($0)" }
        arr[1] = "l2X"
        arr[18] = "l19X"
        let d = diff(old, arr.joined(separator: "\n"))
        var expected = (1...20).map { "l\($0)" }
        expected[1] = "l2X"  // first accepted, second rejected
        #expect(PartialEdit.reconstruct(d, rejecting: [1]) == expected.joined(separator: "\n"))
    }
}
