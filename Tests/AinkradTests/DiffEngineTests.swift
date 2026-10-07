import Foundation
import Testing

@testable import Ainkrad

@Suite struct DiffEngineTests {
    @Test func twoSeparatedChangesProduceTwoHunks() {
        let old = (1...20).map { "line \($0)" }.joined(separator: "\n")
        var lines = (1...20).map { "line \($0)" }
        lines[2] = "line 3 CHANGED"
        lines[17] = "line 18 CHANGED"
        let new = lines.joined(separator: "\n")
        let diff = DiffEngine.compute(old: old, new: new, path: "/f.txt", context: 2)
        #expect(diff.hunks.count == 2)  // gaps > 2*context split the changes
        #expect(diff.path == "/f.txt")
        #expect(diff.original == old)
    }

    @Test func insertionOnly() {
        let diff = DiffEngine.compute(old: "a\nb", new: "a\nX\nb", path: "/f", context: 2)
        #expect(diff.hunks.count == 1)
        let ins = diff.hunks[0].lines.filter { $0.kind == .insertion }
        #expect(ins.map(\.text) == ["X"])
        #expect(diff.hunks[0].lines.contains { $0.kind == .deletion } == false)
    }

    @Test func newFileIsSingleAllInsertionHunk() {
        let diff = DiffEngine.compute(old: "", new: "x\ny", path: "/f", context: 2)
        #expect(diff.hunks.count == 1)
        #expect(diff.hunks[0].lines.allSatisfy { $0.kind == .insertion })
        #expect(diff.hunks[0].newLines == ["x", "y"])
    }

    @Test func identicalHasNoHunks() {
        #expect(DiffEngine.compute(old: "a\nb", new: "a\nb", path: "/f").hunks.isEmpty)
    }
}
