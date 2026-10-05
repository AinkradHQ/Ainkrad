import CoreGraphics
import Foundation
import Testing

@testable import Ainkrad

@Suite("Flat pane layer placement")
@MainActor
struct WorkspacePaneLayerTests {

    private let size = CGSize(width: 1000, height: 800)

    private func workspace(panes: Int, mode: WorkspaceViewMode = .split) -> Workspace {
        let ws = Workspace(name: "W", viewMode: mode)
        for _ in 0..<panes { _ = ws.tileLayout.openApp("terminal") }
        return ws
    }

    @Test("every pane in the workspace gets exactly one placement")
    func everyPaneIsPlaced() {
        let ws = workspace(panes: 3)
        let placements = PaneGeometryResolver.placements(
            for: ws, in: size, carouselOffsetX: 0, isActiveWorkspace: true)

        #expect(placements.count == 3)
        #expect(Set(placements.map(\.block.id)) == Set(ws.tileLayout.blocks.map(\.id)))
    }

    /// The property the whole refactor rests on: a pane's placement is a pure
    /// function of its workspace, so the same Block moved to another workspace
    /// is re-placed rather than re-created.
    @Test("a pane moved to another workspace keeps its identity and is placed by its new home")
    func movedPaneKeepsIdentity() {
        let source = workspace(panes: 2)
        let destination = workspace(panes: 0)
        let block = source.tileLayout.blocks[0]

        source.tileLayout.close(block.id)
        destination.tileLayout.adopt(block)

        let sourcePlacements = PaneGeometryResolver.placements(
            for: source, in: size, carouselOffsetX: 0, isActiveWorkspace: true)
        let destinationPlacements = PaneGeometryResolver.placements(
            for: destination, in: size, carouselOffsetX: size.width, isActiveWorkspace: false)

        #expect(!sourcePlacements.contains { $0.block.id == block.id })
        #expect(destinationPlacements.map(\.block.id) == [block.id])
        // Same object, not a copy — this is what keeps the AppKit view alive.
        #expect(destinationPlacements[0].block === block)
    }

    @Test("a workspace's carousel offset shifts all of its panes and nothing else")
    func carouselOffsetShiftsPanes() {
        let ws = workspace(panes: 2)
        let atRest = PaneGeometryResolver.placements(
            for: ws, in: size, carouselOffsetX: 0, isActiveWorkspace: true)
        let shifted = PaneGeometryResolver.placements(
            for: ws, in: size, carouselOffsetX: size.width, isActiveWorkspace: true)

        for (rest, shift) in zip(atRest, shifted) {
            #expect(shift.frame.minX == rest.frame.minX + size.width)
            #expect(shift.frame.minY == rest.frame.minY)
            #expect(shift.frame.size == rest.frame.size)
        }
    }

    @Test("panes are inset into the canvas, never drawn at the workspace's edge")
    func panesRespectCanvasInsets() {
        let ws = workspace(panes: 1)
        let placement = PaneGeometryResolver.placements(
            for: ws, in: size, carouselOffsetX: 0, isActiveWorkspace: true)[0]
        let canvas = PaneCanvasMetrics.canvasRect(in: size, showsTabStrip: false)

        #expect(placement.frame.minX >= canvas.minX)
        #expect(placement.frame.minY >= canvas.minY)
        #expect(placement.frame.maxX <= canvas.maxX + 0.001)
        #expect(placement.frame.maxY <= canvas.maxY + 0.001)
    }

    @Test("in Focus Mode every pane is held at full canvas size and only the focused one shows")
    func focusModeStacksPanesAtFullSize() {
        let ws = workspace(panes: 3, mode: .focus)
        let focused = ws.tileLayout.blocks[1]
        ws.tileLayout.focus(focused.id)

        let placements = PaneGeometryResolver.placements(
            for: ws, in: size, carouselOffsetX: 0, isActiveWorkspace: true)
        let canvas = PaneCanvasMetrics.canvasRect(in: size, showsTabStrip: true)

        // All at full canvas size — holding them there is what makes switching
        // a pure visibility swap with no terminal reflow.
        for placement in placements {
            #expect(placement.frame.size == canvas.size)
            #expect(placement.isInFocusMode)
        }
        #expect(placements.filter(\.isVisible).map(\.block.id) == [focused.id])
    }

    @Test("Focus Mode with a single pane shows no tab strip, so its pane starts higher")
    func lonePaneHasNoStrip() {
        let ws = workspace(panes: 1, mode: .focus)
        #expect(!PaneGeometryResolver.showsTabStrip(ws))
        #expect(!PaneGeometryResolver.isInFocusMode(ws))

        let placement = PaneGeometryResolver.placements(
            for: ws, in: size, carouselOffsetX: 0, isActiveWorkspace: true)[0]
        #expect(placement.frame.minY == PaneCanvasMetrics.canvasRect(in: size, showsTabStrip: false).minY)
    }

    @Test("no pane of an inactive workspace is visible, whatever its layout says")
    func inactiveWorkspacePanesAreHidden() {
        let ws = workspace(panes: 2)
        let placements = PaneGeometryResolver.placements(
            for: ws, in: size, carouselOffsetX: -size.width, isActiveWorkspace: false)

        #expect(placements.count == 2)
        #expect(placements.allSatisfy { !$0.isVisible })
    }

    @Test("in Split Mode the panes tile the canvas without overlapping")
    func splitPanesDoNotOverlap() {
        let ws = workspace(panes: 3)
        let frames = PaneGeometryResolver.placements(
            for: ws, in: size, carouselOffsetX: 0, isActiveWorkspace: true
        ).map(\.frame)

        for i in frames.indices {
            for j in frames.indices where j > i {
                #expect(!frames[i].intersects(frames[j]))
            }
        }
    }
}
