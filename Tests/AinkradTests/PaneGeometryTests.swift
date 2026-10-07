import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import Ainkrad

/// Characterization of the pixel geometry the pane layer and the seams are
/// positioned from (`TileLayout.paneGeometry`), and of the drop delegate's
/// nearest-edge rule — both pure math that the window-chrome split moves
/// between files, pinned here first so the move cannot change them.
@Suite("Pane geometry and drop edges")
struct PaneGeometryTests {

    // MARK: - paneGeometry

    @Test("an empty layout has no frames and no seams")
    func emptyLayoutHasNoGeometry() {
        let geometry = TileLayout().paneGeometry(in: CGSize(width: 300, height: 200), gap: 8)
        #expect(geometry.frames.isEmpty)
        #expect(geometry.seams.isEmpty)
    }

    @Test("a single pane fills the whole canvas and draws no seam")
    func singlePaneFillsCanvas() {
        let layout = TileLayout()
        let a = layout.openApp("a")

        let geometry = layout.paneGeometry(in: CGSize(width: 300, height: 200), gap: 8)

        #expect(geometry.frames == [a.id: CGRect(x: 0, y: 0, width: 300, height: 200)])
        #expect(geometry.seams.isEmpty)
    }

    @Test("a vertical split stacks rows and puts a horizontal-gap seam between them")
    func verticalSplitStacksRows() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        layout.move(b.id, to: a.id, edge: .bottom)

        let geometry = layout.paneGeometry(in: CGSize(width: 100, height: 208), gap: 8)

        #expect(geometry.frames[a.id] == CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(geometry.frames[b.id] == CGRect(x: 0, y: 108, width: 100, height: 100))
        let seam = geometry.seams.first
        #expect(geometry.seams.count == 1)
        #expect(seam?.axis == .vertical)
        #expect(seam?.frame == CGRect(x: 0, y: 100, width: 100, height: 8))
        #expect(seam?.containerOrigin == 0)
        #expect(seam?.containerLength == 208)
    }

    @Test("a nested container's seam carries its path, its id and its own extent")
    func nestedSeamCarriesPathAndExtent() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        let c = layout.openApp("c")
        layout.move(c.id, to: b.id, edge: .bottom)

        let geometry = layout.paneGeometry(in: CGSize(width: 408, height: 308), gap: 8)

        #expect(geometry.frames[a.id] == CGRect(x: 0, y: 0, width: 200, height: 308))
        #expect(geometry.frames[b.id] == CGRect(x: 208, y: 0, width: 200, height: 150))
        #expect(geometry.frames[c.id] == CGRect(x: 208, y: 158, width: 200, height: 150))

        let root = geometry.seams.first { $0.path.isEmpty }
        #expect(root?.id == "#0")
        #expect(root?.axis == .horizontal)
        #expect(root?.containerOrigin == 0)
        #expect(root?.containerLength == 408)

        let nested = geometry.seams.first { $0.path == [1] }
        #expect(nested?.id == "1#0")
        #expect(nested?.axis == .vertical)
        #expect(nested?.index == 0)
        #expect(nested?.frame == CGRect(x: 208, y: 150, width: 200, height: 8))
        #expect(nested?.containerOrigin == 0)
        #expect(nested?.containerLength == 308)
    }

    @Test("stored fractions set the pane widths, after the gaps are taken out")
    func storedFractionsSetWidths() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        layout.setBoundary(path: [], after: 0, to: 0.25)

        let geometry = layout.paneGeometry(in: CGSize(width: 408, height: 100), gap: 8)

        #expect(geometry.frames[a.id] == CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(geometry.frames[b.id] == CGRect(x: 108, y: 0, width: 300, height: 100))
        #expect(geometry.seams.first?.frame == CGRect(x: 100, y: 0, width: 8, height: 100))
    }

    @Test("collapsing to a nested pane gives it the whole canvas and every other pane zero size")
    func collapseToNestedPane() {
        let layout = TileLayout()
        let a = layout.openApp("a")
        let b = layout.openApp("b")
        let c = layout.openApp("c")
        layout.move(c.id, to: b.id, edge: .bottom)

        let geometry = layout.paneGeometry(in: CGSize(width: 400, height: 300), gap: 8, collapseTo: c.id)

        #expect(geometry.frames[c.id] == CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(geometry.frames[a.id]?.width == 0)
        #expect(geometry.frames[b.id]?.height == 0)
        #expect(geometry.frames.count == 3)
        #expect(geometry.seams.isEmpty)
    }

    // MARK: - PaneEdgeDropDelegate.nearestEdge

    @MainActor
    private func delegate(size: CGSize) -> PaneEdgeDropDelegate {
        PaneEdgeDropDelegate(
            targetBlockID: UUID(),
            tileLayout: TileLayout(),
            size: { size },
            edge: .constant(nil)
        )
    }

    @Test("a pane with no size yet falls back to the trailing edge")
    @MainActor
    func zeroSizeFallsBackToTrailing() {
        #expect(delegate(size: .zero).nearestEdge(to: CGPoint(x: 0, y: 0)) == .trailing)
        #expect(delegate(size: CGSize(width: 100, height: 0)).nearestEdge(to: CGPoint(x: 0, y: 0)) == .trailing)
    }

    @Test("the half the pointer is furthest into along the dominant axis wins")
    @MainActor
    func dominantAxisPicksTheEdge() {
        let drop = delegate(size: CGSize(width: 200, height: 100))
        #expect(drop.nearestEdge(to: CGPoint(x: 10, y: 50)) == .leading)
        #expect(drop.nearestEdge(to: CGPoint(x: 190, y: 50)) == .trailing)
        #expect(drop.nearestEdge(to: CGPoint(x: 100, y: 5)) == .top)
        #expect(drop.nearestEdge(to: CGPoint(x: 100, y: 95)) == .bottom)
    }

    @Test("distance is measured relative to the pane's size, not in points")
    @MainActor
    func distanceIsRelative() {
        // 120pt in from the left of a 400pt-wide pane is 0.2 off centre; 4pt
        // down a 40pt-tall one is 0.4 off — so the top wins although the
        // pointer is far fewer points from the left edge than that sounds.
        let drop = delegate(size: CGSize(width: 400, height: 40))
        #expect(drop.nearestEdge(to: CGPoint(x: 120, y: 4)) == .top)
        #expect(drop.nearestEdge(to: CGPoint(x: 20, y: 18)) == .leading)
    }

    @Test("an exact tie between the axes resolves vertically")
    @MainActor
    func tieResolvesVertically() {
        let drop = delegate(size: CGSize(width: 100, height: 100))
        #expect(drop.nearestEdge(to: CGPoint(x: 50, y: 50)) == .bottom)
        #expect(drop.nearestEdge(to: CGPoint(x: 0, y: 0)) == .top)
    }
}
