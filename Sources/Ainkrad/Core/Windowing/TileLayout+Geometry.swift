import Foundation

/// Unit-space geometry over the split tree: directional focus movement and
/// keyboard resizing (⌘/⌘⇧ arrows). Split out of `TileLayout.swift` to keep
/// it under the 500-line ceiling; the pixel geometry the views render from is
/// `paneGeometry` in `PaneGeometry.swift`.
extension TileLayout {
    // MARK: - Geometry (keyboard navigation & resize)

    /// Unit-space (0…1 × 0…1) frames for every pane, ignoring gaps —
    /// drives directional focus movement.
    func paneFrames() -> [UUID: CGRect] {
        guard let root else { return [:] }
        var frames: [UUID: CGRect] = [:]
        Self.collectFrames(root, rect: CGRect(x: 0, y: 0, width: 1, height: 1), into: &frames)
        return frames
    }

    /// Moves focus to the nearest pane in the given direction (⌘arrows).
    func focusNeighbor(_ direction: PaneDirection) {
        guard let focusedBlockID else { return }
        let frames = paneFrames()
        guard let origin = frames[focusedBlockID] else { return }

        var best: (id: UUID, distance: CGFloat)?
        for (id, frame) in frames where id != focusedBlockID {
            let isCandidate: Bool
            switch direction {
            case .left:
                isCandidate =
                    frame.midX < origin.midX - 0.001 && overlaps(frame.minY..<frame.maxY, origin.minY..<origin.maxY)
            case .right:
                isCandidate =
                    frame.midX > origin.midX + 0.001 && overlaps(frame.minY..<frame.maxY, origin.minY..<origin.maxY)
            case .up:
                isCandidate =
                    frame.midY < origin.midY - 0.001 && overlaps(frame.minX..<frame.maxX, origin.minX..<origin.maxX)
            case .down:
                isCandidate =
                    frame.midY > origin.midY + 0.001 && overlaps(frame.minX..<frame.maxX, origin.minX..<origin.maxX)
            }
            guard isCandidate else { continue }
            let dx = frame.midX - origin.midX
            let dy = frame.midY - origin.midY
            let distance = dx * dx + dy * dy
            if best == nil || distance < best!.distance {
                best = (id, distance)
            }
        }
        if let best {
            focus(best.id)
        }
    }

    /// Grows the focused pane toward `direction` by `delta` (⌘⇧arrows):
    /// finds the nearest ancestor container along that axis where the
    /// focused subtree has a boundary on that side, and shifts it.
    func resizeFocused(_ direction: PaneDirection, delta: Double = 0.06) {
        guard let root, let focusedBlockID else { return }
        guard let path = Self.pathTo(focusedBlockID, in: root) else { return }
        let axis: PaneAxis = (direction == .left || direction == .right) ? .horizontal : .vertical
        let growsTrailing = direction == .right || direction == .down

        for depth in stride(from: path.count - 1, through: 0, by: -1) {
            let containerPath = Array(path.prefix(depth))
            let childIndex = path[depth]
            guard let container = Self.node(at: ArraySlice(containerPath), in: root),
                case .split(let containerAxis, let children, let fractions) = container,
                containerAxis == axis
            else { continue }

            let boundaryIndex = growsTrailing ? childIndex : childIndex - 1
            guard boundaryIndex >= 0, boundaryIndex < children.count - 1 else { continue }

            let cumulative = fractions.prefix(boundaryIndex + 1).reduce(0, +)
            let newPosition = cumulative + (growsTrailing ? delta : -delta)
            setBoundary(path: containerPath, after: boundaryIndex, to: newPosition)
            onStructuralChange?()
            return
        }
    }

    private func overlaps(_ a: Range<CGFloat>, _ b: Range<CGFloat>) -> Bool {
        a.lowerBound < b.upperBound && b.lowerBound < a.upperBound
    }
}
