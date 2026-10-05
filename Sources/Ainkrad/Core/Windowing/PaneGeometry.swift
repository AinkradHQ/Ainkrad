import Foundation

/// Where a resize seam sits between two siblings, in canvas pixels, plus
/// what it addresses in the tree. `containerOrigin`/`containerLength` span
/// the parent container along its axis so a drag location converts to the
/// cumulative 0…1 position `setBoundary` expects.
struct SeamPlacement: Identifiable, Equatable {
    let id: String
    let axis: PaneAxis
    let frame: CGRect
    let path: [Int]
    let index: Int
    let containerOrigin: CGFloat
    let containerLength: CGFloat
}

extension TileLayout {
    /// Computes every pane's pixel frame and every seam's placement for a
    /// canvas of `size`. The TREE drives only this geometry — rendering
    /// keeps one stable view per pane, so structural changes (moves,
    /// splits, closes) reposition views instead of re-creating them, and
    /// running sessions survive. With `collapseTo` set (Focus Mode), that
    /// pane's path takes everything and gaps/seams disappear; collapsed
    /// panes get zero-sized frames but remain mounted.
    func paneGeometry(in size: CGSize, gap: CGFloat, collapseTo: UUID? = nil) -> (
        frames: [UUID: CGRect], seams: [SeamPlacement]
    ) {
        guard let root else { return ([:], []) }
        var frames: [UUID: CGRect] = [:]
        var seams: [SeamPlacement] = []
        collectGeometry(
            root,
            rect: CGRect(origin: .zero, size: size),
            gap: collapseTo == nil ? gap : 0,
            collapseTo: collapseTo,
            path: [],
            frames: &frames,
            seams: &seams
        )
        return (frames, seams)
    }

    private func collectGeometry(
        _ node: PaneNode,
        rect: CGRect,
        gap: CGFloat,
        collapseTo: UUID?,
        path: [Int],
        frames: inout [UUID: CGRect],
        seams: inout [SeamPlacement]
    ) {
        switch node {
        case .leaf(let block):
            frames[block.id] = rect

        case .split(let axis, let children, let storedFractions):
            let fractions: [Double]
            if let collapseTo {
                fractions = children.map { subtreeContains(collapseTo, in: $0) ? 1.0 : 0.0 }
            } else if storedFractions.count == children.count {
                fractions = storedFractions
            } else {
                fractions = Array(repeating: 1.0 / Double(max(children.count, 1)), count: children.count)
            }

            let totalLength = axis == .horizontal ? rect.width : rect.height
            let available = max(totalLength - CGFloat(children.count - 1) * gap, 0)
            let containerOrigin = axis == .horizontal ? rect.minX : rect.minY
            var cursor = containerOrigin

            for (index, child) in children.enumerated() {
                let length = available * CGFloat(fractions[index])
                let childRect =
                    axis == .horizontal
                    ? CGRect(x: cursor, y: rect.minY, width: length, height: rect.height)
                    : CGRect(x: rect.minX, y: cursor, width: rect.width, height: length)

                collectGeometry(
                    child, rect: childRect, gap: gap, collapseTo: collapseTo, path: path + [index], frames: &frames,
                    seams: &seams)
                cursor += length

                if index < children.count - 1 {
                    if collapseTo == nil {
                        let seamRect =
                            axis == .horizontal
                            ? CGRect(x: cursor, y: rect.minY, width: gap, height: rect.height)
                            : CGRect(x: rect.minX, y: cursor, width: rect.width, height: gap)
                        seams.append(
                            SeamPlacement(
                                id: "\(path.map(String.init).joined(separator: "."))#\(index)",
                                axis: axis,
                                frame: seamRect,
                                path: path,
                                index: index,
                                containerOrigin: containerOrigin,
                                containerLength: totalLength
                            ))
                    }
                    cursor += gap
                }
            }
        }
    }
}
