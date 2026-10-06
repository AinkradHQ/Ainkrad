import SwiftUI

/// The Termius drop mechanism: while a dragged pane hovers, the nearest
/// half of this pane is tracked (for the highlight); dropping performs
/// `TileLayout.move` — joining as an equal sibling on parallel edges, or
/// wrapping this pane into a stacked pair on perpendicular ones.
struct PaneEdgeDropDelegate: DropDelegate {
    let targetBlockID: UUID
    let tileLayout: TileLayout
    let size: () -> CGSize
    @Binding var edge: PaneEdge?

    func validateDrop(info: DropInfo) -> Bool {
        guard let dragging = tileLayout.draggingBlockID else { return false }
        return dragging != targetBlockID
    }

    func dropEntered(info: DropInfo) {
        edge = nearestEdge(to: info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        edge = nearestEdge(to: info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        edge = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let landingEdge = edge ?? nearestEdge(to: info.location)
        defer {
            edge = nil
            tileLayout.draggingBlockID = nil
        }
        guard let dragging = tileLayout.draggingBlockID else { return false }
        tileLayout.move(dragging, to: targetBlockID, edge: landingEdge)
        return true
    }

    func nearestEdge(to location: CGPoint) -> PaneEdge {
        let bounds = size()
        guard bounds.width > 0, bounds.height > 0 else { return .trailing }
        let dx = location.x / bounds.width - 0.5
        let dy = location.y / bounds.height - 0.5
        if abs(dx) > abs(dy) {
            return dx < 0 ? .leading : .trailing
        } else {
            return dy < 0 ? .top : .bottom
        }
    }
}
