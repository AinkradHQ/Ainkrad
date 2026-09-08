import Foundation
import CoreGraphics
import Testing
@testable import Ainkrad

@Suite("ScryLayout")
struct ScryLayoutTests {
    private func element(_ id: String, _ kind: ScryElementKind,
                         _ hint: ScrySizeHint) -> ScryElement {
        ScryElement(id: id, kind: kind, body: "", sizeHint: hint)
    }

    private let wide = CGSize(width: 1200, height: 900)

    @Test("column count grows with width and never drops below one")
    func columns() {
        #expect(ScryLayout.columnCount(for: 300) == 1)
        #expect(ScryLayout.columnCount(for: 1200) >= 3)
        #expect(ScryLayout.columnCount(for: 0) == 1)
    }

    @Test("newest element is placed at the top-left")
    func newestFirst() {
        let els = [element("old", .text, .medium), element("new", .text, .medium)]
        let f = ScryLayout.frames(for: els, in: wide, overrides: [:])
        let new = f["new"]!, old = f["old"]!
        #expect(new.y <= old.y)
        #expect(new.x < old.x || new.y < old.y)
    }

    @Test("every element gets exactly one frame")
    func totalCoverage() {
        let els = (0..<7).map { element("e\($0)", .text, .medium) }
        let f = ScryLayout.frames(for: els, in: wide, overrides: [:])
        #expect(f.count == 7)
    }

    @Test("a full-width card spans the row alone")
    func fullSpansRow() {
        let els = [element("t", .table, .full)]
        let f = ScryLayout.frames(for: els, in: wide, overrides: [:])
        let r = f["t"]!
        #expect(r.width > wide.width - 2 * ScryLayout.padding - 1)
    }

    @Test("small cards share a row rather than stacking")
    func smallCardsShareARow() {
        let els = [element("a", .status, .small), element("b", .status, .small)]
        let f = ScryLayout.frames(for: els, in: wide, overrides: [:])
        #expect(f["a"]!.y == f["b"]!.y)
        #expect(f["a"]!.x != f["b"]!.x)
    }

    @Test("no two auto-placed cards share the same origin")
    func noPileUp() {
        let els = (0..<10).map { element("e\($0)", .text, .medium) }
        let f = ScryLayout.frames(for: els, in: wide, overrides: [:])
        let origins = Set(f.values.map { "\($0.x)x\($0.y)" })
        #expect(origins.count == 10)
    }

    @Test("an overridden card is excluded and the flow re-packs")
    func overrideLeavesFlow() {
        let els = [element("a", .text, .medium), element("b", .text, .medium)]
        let pinned = ScryRect(x: 700, y: 500, width: 300, height: 200)
        let f = ScryLayout.frames(for: els, in: wide, overrides: ["a": pinned])
        #expect(f["a"] == nil)
        #expect(f["b"] != nil)
        // b takes the first slot now that a is out of the flow.
        let alone = ScryLayout.frames(for: [els[1]], in: wide, overrides: [:])
        #expect(f["b"]! == alone["b"]!)
    }

    @Test("identical input yields identical output")
    func deterministic() {
        let els = (0..<5).map { element("e\($0)", .chart, .large) }
        #expect(ScryLayout.frames(for: els, in: wide, overrides: [:])
                == ScryLayout.frames(for: els, in: wide, overrides: [:]))
    }

    @Test("content height spans an overridden card placed below the flow")
    func contentHeightSpansOverrides() {
        let els = [element("a", .text, .medium)]
        let flowOnly = ScryLayout.contentHeight(for: els, in: wide, overrides: [:])
        let farBelow = ScryRect(x: 100, y: 3000, width: 300, height: 200)
        let withOverride = ScryLayout.contentHeight(for: els, in: wide, overrides: ["a": farBelow])
        #expect(withOverride > flowOnly)
        #expect(withOverride >= 3000 + 200)
    }
}
