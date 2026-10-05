import Foundation
import Testing

@testable import Ainkrad

@Suite("TileLayout (N-ary split tree)")
struct TileLayoutTests {

    // MARK: - Basics

    @Test("a new layout starts empty with no focused pane")
    func startsEmpty() {
        let layout = TileLayout()
        #expect(layout.isEmpty)
        #expect(layout.blocks.isEmpty)
        #expect(layout.focusedBlockID == nil)
    }

    @Test("opening apps appends equal top-level columns, newest focused")
    func openAppendsEqualColumns() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        let c = layout.openApp("c")

        guard case .split(let axis, let children, let fractions) = layout.root else {
            Issue.record("expected a root split")
            return
        }
        #expect(axis == .horizontal)
        #expect(children == [.leaf(a), .leaf(b), .leaf(c)])
        #expect(fractions.count == 3)
        #expect(abs(fractions[0] - 1.0 / 3.0) < 0.0001)
        #expect(layout.focusedBlockID == c.id)
        #expect(layout.appIDs == ["a", "b", "c"])
    }

    @Test("a single pane fills the canvas")
    func singlePaneIsRootLeaf() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        #expect(layout.root == .leaf(a))
    }

    // MARK: - Close

    @Test("closing a pane re-equalizes its siblings")
    func closeReEqualizesSiblings() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        let c = layout.openApp("c")

        layout.close(b.id)

        guard case .split(_, let children, let fractions) = layout.root else {
            Issue.record("expected a root split")
            return
        }
        #expect(children == [.leaf(a), .leaf(c)])
        #expect(fractions == [0.5, 0.5])
    }

    @Test("a container left with one child collapses into it")
    func singleChildContainerCollapses() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        // Stack b under a: root becomes a single vertical container.
        layout.move(b.id, to: a.id, edge: .bottom)

        layout.close(b.id)

        #expect(layout.root == .leaf(a))
    }

    @Test("closing the focused pane focuses its predecessor in pane order")
    func closingFocusedFocusesPredecessor() {
        let layout = TileLayout()
        _ = layout.openApp("a")
        let b = layout.openApp("b")
        let c = layout.openApp("c")

        layout.close(c.id)

        #expect(layout.focusedBlockID == b.id)
    }

    @Test("closing the last pane returns to the empty state")
    func closingLastReturnsToEmpty() {
        let layout = TileLayout()
        let a = layout.openApp("a")

        layout.close(a.id)

        #expect(layout.isEmpty)
        #expect(layout.focusedBlockID == nil)
    }

    // MARK: - Move: parallel drops join the container as an equal sibling

    @Test("dropping on a side edge inserts as an equal sibling column")
    func parallelDropInsertsSibling() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        let c = layout.openApp("c")

        // Drag c onto a's leading edge: [c, a, b] as equal thirds.
        layout.move(c.id, to: a.id, edge: .leading)

        guard case .split(let axis, let children, let fractions) = layout.root else {
            Issue.record("expected a root split")
            return
        }
        #expect(axis == .horizontal)
        #expect(children == [.leaf(c), .leaf(a), .leaf(b)])
        #expect(abs(fractions[0] - 1.0 / 3.0) < 0.0001)
        #expect(layout.focusedBlockID == c.id)
    }

    @Test("dropping on a trailing edge lands after the target")
    func trailingDropLandsAfterTarget() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        let c = layout.openApp("c")

        layout.move(a.id, to: b.id, edge: .trailing)

        guard case .split(_, let children, _) = layout.root else {
            Issue.record("expected a root split")
            return
        }
        #expect(children == [.leaf(b), .leaf(a), .leaf(c)])
    }

    // MARK: - Move: perpendicular drops wrap the target

    @Test("dropping on a bottom edge stacks the pane under the target")
    func perpendicularDropWrapsTarget() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        let c = layout.openApp("c")

        // Drag c under b: b's slot becomes a vertical pair, thirds → halves.
        layout.move(c.id, to: b.id, edge: .bottom)

        guard case .split(let axis, let children, let fractions) = layout.root else {
            Issue.record("expected a root split")
            return
        }
        #expect(axis == .horizontal)
        #expect(fractions == [0.5, 0.5])
        #expect(children[0] == .leaf(a))
        #expect(children[1] == .split(axis: .vertical, children: [.leaf(b), .leaf(c)], fractions: [0.5, 0.5]))
    }

    @Test("moving the last sibling out of a container collapses it")
    func movingOutCollapsesContainer() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        layout.move(b.id, to: a.id, edge: .bottom)
        // Root is now a vertical pair [a, b].

        layout.move(b.id, to: a.id, edge: .trailing)

        #expect(layout.root == .split(axis: .horizontal, children: [.leaf(a), .leaf(b)], fractions: [0.5, 0.5]))
    }

    @Test("moving a pane onto itself is a no-op")
    func moveOntoSelfIsNoOp() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        let before = layout.root

        layout.move(a.id, to: a.id, edge: .leading)

        #expect(layout.root == before)
        _ = b
    }

    // MARK: - Resize

    @Test("setBoundary adjusts adjacent sibling fractions within a container")
    func setBoundaryAdjustsFractions() {
        let layout = TileLayout()
        _ = layout.openApp("a")
        _ = layout.openApp("b")
        _ = layout.openApp("c")

        // Boundary after the first third moved to 50%.
        layout.setBoundary(path: [], after: 0, to: 0.5)

        guard case .split(_, _, let fractions) = layout.root else {
            Issue.record("expected a root split")
            return
        }
        #expect(abs(fractions[0] - 0.5) < 0.0001)
        #expect(abs(fractions[1] - (1.0 / 3.0 + 1.0 / 3.0 - 0.5)) < 0.0001)
        #expect(abs(fractions[2] - 1.0 / 3.0) < 0.0001)
    }

    @Test("setBoundary clamps so no sibling collapses below its minimum")
    func setBoundaryClamps() {
        let layout = TileLayout()
        _ = layout.openApp("a")
        _ = layout.openApp("b")

        layout.setBoundary(path: [], after: 0, to: 0.99)

        guard case .split(_, _, let fractions) = layout.root else {
            Issue.record("expected a root split")
            return
        }
        #expect(fractions[0] <= 0.9 + 0.0001)
        #expect(fractions[1] >= 0.1 - 0.0001)
    }

    // MARK: - Split commands

    @Test("split(right) opens a new pane of the same app as an equal sibling")
    func splitRightInsertsSibling() {
        let layout = TileLayout()
        let a = layout.openApp("terminal")
        _ = layout.openApp("settings")

        let created = layout.split(a.id, edge: .trailing)

        guard case .split(let axis, let children, let fractions) = layout.root else {
            Issue.record("expected a root split")
            return
        }
        #expect(axis == .horizontal)
        #expect(children.count == 3)
        #expect(layout.appIDs == ["terminal", "terminal", "settings"])
        #expect(abs(fractions[0] - 1.0 / 3.0) < 0.0001)
        #expect(layout.focusedBlockID == created?.id)
    }

    @Test("splitFocused(down) wraps the focused pane into a stacked pair")
    func splitFocusedDownWraps() {
        let layout = TileLayout()
        _ = layout.openApp("terminal")
        let b = layout.openApp("settings")

        layout.splitFocused(.bottom)

        guard case .split(_, let children, _) = layout.root,
            case .split(let innerAxis, let inner, _) = children[1]
        else {
            Issue.record("expected nested split under the focused pane")
            return
        }
        #expect(innerAxis == .vertical)
        #expect(inner.count == 2)
        if case .leaf(let first) = inner[0] { #expect(first.id == b.id) }
        #expect(layout.appIDs == ["terminal", "settings", "settings"])
    }

    // MARK: - Duplicate / reset

    @Test("duplicate copies a pane beside itself")
    func duplicateCopiesPane() {
        let layout = TileLayout()
        let a = layout.openApp("terminal")

        let copy = layout.duplicate(a.id)

        #expect(copy?.appID == "terminal")
        #expect(layout.appIDs == ["terminal", "terminal"])
        #expect(layout.focusedBlockID == copy?.id)
    }

    @Test("resetLayout re-equalizes every container")
    func resetLayoutEqualizes() {
        let layout = TileLayout()
        _ = layout.openApp("a")
        _ = layout.openApp("b")
        layout.setBoundary(path: [], after: 0, to: 0.8)

        layout.resetLayout()

        guard case .split(_, _, let fractions) = layout.root else {
            Issue.record("expected a root split")
            return
        }
        #expect(fractions == [0.5, 0.5])
    }

    // MARK: - Geometry & keyboard

    @Test("paneFrames tiles the unit square by the stored fractions")
    func paneFramesTileUnitSquare() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")

        let frames = layout.paneFrames()

        #expect(frames[a.id] == CGRect(x: 0, y: 0, width: 0.5, height: 1))
        #expect(frames[b.id] == CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
    }

    @Test("focusNeighbor moves focus directionally, no-op at edges")
    func focusNeighborMovesDirectionally() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        let c = layout.openApp("c")
        layout.focus(a.id)

        layout.focusNeighbor(.right)
        #expect(layout.focusedBlockID == b.id)

        layout.focusNeighbor(.right)
        #expect(layout.focusedBlockID == c.id)

        layout.focusNeighbor(.right)
        #expect(layout.focusedBlockID == c.id)

        layout.focusNeighbor(.left)
        #expect(layout.focusedBlockID == b.id)
    }

    @Test("focusNeighbor crosses into stacked panes vertically")
    func focusNeighborCrossesVertically() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        layout.move(b.id, to: a.id, edge: .bottom)
        layout.focus(a.id)

        layout.focusNeighbor(.down)
        #expect(layout.focusedBlockID == b.id)

        layout.focusNeighbor(.up)
        #expect(layout.focusedBlockID == a.id)
    }

    @Test("resizeFocused grows the focused pane toward the direction")
    func resizeFocusedGrows() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        _ = layout.openApp("b")
        layout.focus(a.id)

        layout.resizeFocused(.right)

        guard case .split(_, _, let fractions) = layout.root else {
            Issue.record("expected a root split")
            return
        }
        // One keypress moves the boundary by the default step (6%).
        #expect(abs(fractions[0] - 0.56) < 0.0001)
    }

    // MARK: - Pixel geometry (flat rendering)

    @Test("paneGeometry frames account for the gap and cover the canvas")
    func paneGeometryFramesAccountForGap() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")

        let geometry = layout.paneGeometry(in: CGSize(width: 208, height: 100), gap: 8)

        #expect(geometry.frames[a.id] == CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(geometry.frames[b.id] == CGRect(x: 108, y: 0, width: 100, height: 100))
        #expect(geometry.seams.count == 1)
        #expect(geometry.seams[0].frame == CGRect(x: 100, y: 0, width: 8, height: 100))
        #expect(geometry.seams[0].path == [])
        #expect(geometry.seams[0].index == 0)
    }

    @Test("paneGeometry with collapseTo gives the target everything, zero to the rest, no seams")
    func paneGeometryCollapses() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")

        let geometry = layout.paneGeometry(in: CGSize(width: 200, height: 100), gap: 8, collapseTo: a.id)

        #expect(geometry.frames[a.id] == CGRect(x: 0, y: 0, width: 200, height: 100))
        #expect(geometry.frames[b.id]?.width == 0)
        #expect(geometry.seams.isEmpty)
    }

    @Test("every pane gets a frame in nested layouts")
    func paneGeometryCoversNestedLayouts() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        let c = layout.openApp("c")
        layout.move(c.id, to: b.id, edge: .bottom)

        let geometry = layout.paneGeometry(in: CGSize(width: 400, height: 300), gap: 8)

        #expect(geometry.frames.count == 3)
        #expect(geometry.seams.count == 2)
        #expect(geometry.frames[a.id]?.height == 300)
        #expect(geometry.frames[b.id]?.minY == 0)
        #expect(geometry.frames[c.id]!.minY > geometry.frames[b.id]!.minY)
    }

    // MARK: - Persistence

    @Test("a layout snapshot round-trips through JSON with identical structure")
    func snapshotRoundTripsThroughJSON() throws {
        let layout = TileLayout()
        let a = layout.openApp("terminal")
        _ = layout.openApp("settings")
        let c = layout.openApp("terminal")
        layout.move(c.id, to: a.id, edge: .bottom)
        layout.setBoundary(path: [], after: 0, to: 0.7)

        let snapshot = try #require(layout.snapshot())
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(PaneSnapshot.self, from: data)

        let restored = TileLayout()
        restored.apply(decoded)

        #expect(restored.snapshot() == snapshot)
        #expect(restored.appIDs == layout.appIDs)
        #expect(restored.focusedBlockID == restored.blocks.first?.id)
    }
}
