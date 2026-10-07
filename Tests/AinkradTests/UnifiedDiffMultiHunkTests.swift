import Foundation
import Testing

@testable import Ainkrad

@Suite struct UnifiedDiffMultiHunkTests {
    @Test func emitsOneHeaderPerHunk() {
        let old = (1...20).map { "l\($0)" }.joined(separator: "\n")
        var arr = (1...20).map { "l\($0)" }
        arr[1] = "l2X"
        arr[18] = "l19X"
        let out = UnifiedDiff.make(old: old, new: arr.joined(separator: "\n"), path: "/f")
        #expect(out.components(separatedBy: "\n").filter { $0.hasPrefix("@@") }.count == 2)
        #expect(out.contains("+l2X"))
        #expect(out.contains("-l2"))
    }

    @Test func identicalProducesHeaderOnly() {
        let out = UnifiedDiff.make(old: "a\nb", new: "a\nb", path: "/f")
        #expect(out.contains("--- /f"))
        #expect(!out.contains("@@"))
    }
}
