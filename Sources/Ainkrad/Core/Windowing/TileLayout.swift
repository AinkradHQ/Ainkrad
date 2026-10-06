import Foundation
import Observation

/// A container's layout direction: `.horizontal` lays children out as
/// side-by-side columns, `.vertical` stacks them as rows.
enum PaneAxis: Equatable {
    case horizontal
    case vertical
}

/// A direction for keyboard focus movement and resizing (⌘/⌘⇧ arrows).
enum PaneDirection {
    case left, right, up, down
}

/// Which edge of a target pane a dragged pane is dropped on.
enum PaneEdge {
    case leading, trailing, top, bottom

    var axis: PaneAxis {
        switch self {
        case .leading, .trailing: return .horizontal
        case .top, .bottom: return .vertical
        }
    }

    /// Whether the dropped pane lands before the target.
    var insertsFirst: Bool {
        self == .leading || self == .top
    }
}

/// The N-ary split tree (the Termius split-view structure): a node is a
/// pane, or a container of 2+ children sharing one direction with
/// per-child fractions. Siblings in the same direction live flat in ONE
/// container — three columns are one horizontal split at ⅓ each, never
/// nested binary halves.
indirect enum PaneNode: Equatable {
    case leaf(Block)
    case split(axis: PaneAxis, children: [PaneNode], fractions: [Double])
}

/// One workspace's pane layout, copying the Termius split-view mechanism
/// observed from the reference recording:
///
/// - Opening an app appends an equal top-level column.
/// - Dropping a pane on a target's edge *parallel* to the target's
///   container joins that container as an equal sibling (3 panes → equal
///   thirds); a *perpendicular* drop wraps the target into a new 50/50
///   container.
/// - Closing/moving out re-equalizes the affected container and collapses
///   single-child containers.
/// - Sibling boundaries resize (10% minimum). Focus Mode (a workspace-
///   level view mode) renders by collapsing toward the focused pane
///   without touching this tree.
@Observable
final class TileLayout {
    private(set) var root: PaneNode?
    private(set) var focusedBlockID: UUID?
    /// Transient drag context: set while a pane header drag session is
    /// live so drop targets can identify the source.
    var draggingBlockID: UUID?
    /// Invoked after any structural change — persistence hooks in here.
    var onStructuralChange: (() -> Void)?

    private static let minimumFraction = 0.1

    init() {}

    var isEmpty: Bool { root == nil }

    /// Every open pane, in tree (reading) order.
    var blocks: [Block] {
        root.map(Self.collectBlocks) ?? []
    }

    var appIDs: [String] { blocks.map { $0.appID } }

    // MARK: - Operations

    @discardableResult
    func openApp(_ appID: String) -> Block {
        let block = Block(appID: appID)
        appendColumn(block)
        focusedBlockID = block.id
        onStructuralChange?()
        return block
    }

    /// Re-homes an existing pane moved from another workspace, preserving its
    /// block identity. Appended as a new top-level column.
    @discardableResult
    func adopt(_ block: Block) -> Block {
        appendColumn(block)
        focusedBlockID = block.id
        onStructuralChange?()
        return block
    }

    /// Appends `block` as an equal top-level column (the open-app placement).
    private func appendColumn(_ block: Block) {
        switch root {
        case nil:
            root = .leaf(block)
        case .leaf(let existing):
            root = .split(
                axis: .horizontal, children: [.leaf(existing), .leaf(block)], fractions: Self.equalFractions(2))
        case .split(.horizontal, var children, _):
            children.append(.leaf(block))
            root = .split(axis: .horizontal, children: children, fractions: Self.equalFractions(children.count))
        case .split(let axis, let children, let fractions):
            // Root stacks vertically: wrap it beside the new column.
            root = .split(
                axis: .horizontal,
                children: [.split(axis: axis, children: children, fractions: fractions), .leaf(block)],
                fractions: Self.equalFractions(2)
            )
        }
    }

    func close(_ id: UUID) {
        guard let root else { return }
        let paneOrder = blocks
        guard let index = paneOrder.firstIndex(where: { $0.id == id }) else { return }

        self.root = Self.removing(id, from: root)

        if focusedBlockID == id {
            let survivors = blocks
            focusedBlockID = survivors.isEmpty ? nil : survivors[min(max(index - 1, 0), survivors.count - 1)].id
        }
        onStructuralChange?()
    }

    func focus(_ id: UUID) {
        focusedBlockID = id
    }

    /// Drag-to-rearrange: removes the pane from its slot and re-inserts it
    /// on the target's edge — joining the target's container as an equal
    /// sibling when the edge is parallel to it, or wrapping the target
    /// into a new 50/50 container when perpendicular.
    func move(_ id: UUID, to targetID: UUID, edge: PaneEdge) {
        guard id != targetID, let root else { return }
        guard let block = blocks.first(where: { $0.id == id }),
            blocks.contains(where: { $0.id == targetID })
        else { return }

        guard let remaining = Self.removing(id, from: root) else { return }
        guard Self.collectBlocks(remaining).contains(where: { $0.id == targetID }) else { return }

        self.root = Self.inserting(block, at: targetID, edge: edge, in: remaining)
        focusedBlockID = id
        onStructuralChange?()
    }

    /// Moves focus to the pane `offset` places away in TAB ORDER — the order
    /// `blocks` reads in, which is the order the Focus-Mode tab strip shows.
    ///
    /// Distinct from `focusNeighbor`, which walks the split TREE geometrically.
    /// Geometric movement is right for Split Mode, where panes really are laid
    /// out left/right/up/down — but it is wrong for a tab strip, where the panes
    /// are stacked on top of each other and the only order the user can see is
    /// the strip's. Against a nested tree ("two columns, the second split into
    /// three rows") a geometric ⌘→ steps out of the current container and past
    /// its siblings, which is what made arrow navigation appear to skip tabs.
    ///
    /// Clamps at both ends rather than wrapping: arrows in a tab strip are
    /// directional, and silently jumping from the last tab to the first reads as
    /// a skip too.
    func focusAdjacentInOrder(offset: Int) {
        let panes = blocks
        guard !panes.isEmpty else { return }
        guard let current = panes.firstIndex(where: { $0.id == focusedBlockID }) else {
            focus(panes[0].id)
            return
        }
        let target = min(max(current + offset, 0), panes.count - 1)
        guard target != current else { return }
        focus(panes[target].id)
    }

    /// Focuses the pane at `index` in tab order (the ⌥1-9 direct jumps). Out of
    /// range is a no-op, so ⌥7 with three tabs open does nothing rather than
    /// clamping to a tab the user didn't aim at.
    func focusPane(at index: Int) {
        let panes = blocks
        guard panes.indices.contains(index) else { return }
        guard panes[index].id != focusedBlockID else { return }
        focus(panes[index].id)
    }

    /// Renames a pane (its Focus-Mode tab). Routed through the layout rather
    /// than set on the `Block` directly so the new name is persisted with the
    /// rest of the layout — a rename that vanishes on relaunch is not a rename.
    func rename(_ id: UUID, to title: String) {
        guard let block = blocks.first(where: { $0.id == id }) else { return }
        block.rename(to: title)
        onStructuralChange?()
    }

    /// Splits a pane: opens a NEW pane of the same app on the given edge —
    /// joining its container as an equal sibling when the edge is parallel
    /// to it, or wrapping it into a stacked 50/50 pair when perpendicular.
    @discardableResult
    func split(_ id: UUID, edge: PaneEdge) -> Block? {
        guard let root, let source = blocks.first(where: { $0.id == id }) else { return nil }
        // A split inherits the source pane's name — it is the same app, and a
        // renamed pane splitting into an unnamed one reads as a different app.
        let block = Block(appID: source.appID, title: source.title)
        self.root = Self.inserting(block, at: id, edge: edge, in: root)
        focusedBlockID = block.id
        onStructuralChange?()
        return block
    }

    /// Splits the focused pane (⌘D right, ⌘⇧D down).
    @discardableResult
    func splitFocused(_ edge: PaneEdge) -> Block? {
        guard let focusedBlockID else { return nil }
        return split(focusedBlockID, edge: edge)
    }

    /// Drags the boundary after child `index` of the container at `path`
    /// (child indices from the root) to cumulative `position` (0…1 of that
    /// container's extent). Adjacent siblings share the delta; no sibling
    /// collapses below 10%.
    func setBoundary(path: [Int], after index: Int, to position: Double) {
        guard let root else { return }
        self.root = Self.settingBoundary(path: ArraySlice(path), after: index, to: position, in: root)
    }

    /// Whether `node` contains the given pane — Focus Mode's rendering
    /// collapses every sibling outside the focused pane's path.
    func subtreeContains(_ id: UUID, in node: PaneNode) -> Bool {
        Self.collectBlocks(node).contains(where: { $0.id == id })
    }

    /// Duplicates a pane beside itself (same app, fresh instance).
    @discardableResult
    func duplicate(_ id: UUID) -> Block? {
        split(id, edge: .trailing)
    }

    /// Re-equalizes every container's fractions (Reset Layout).
    func resetLayout() {
        guard let root else { return }
        self.root = Self.equalizing(root)
        onStructuralChange?()
    }

    /// Wholesale root replacement (persistence restore). Focus lands on
    /// the first pane.
    func replaceRoot(_ node: PaneNode?) {
        root = node
        focusedBlockID = blocks.first?.id
    }

    // MARK: - Pure tree operations

    private static func equalFractions(_ count: Int) -> [Double] {
        Array(repeating: 1.0 / Double(max(count, 1)), count: count)
    }

    private static func collectBlocks(_ node: PaneNode) -> [Block] {
        switch node {
        case .leaf(let block):
            return [block]
        case .split(_, let children, _):
            return children.flatMap(collectBlocks)
        }
    }

    /// Removes the pane, re-equalizing the container it left and
    /// collapsing containers reduced to one child. Returns nil when the
    /// tree becomes empty.
    private static func removing(_ id: UUID, from node: PaneNode) -> PaneNode? {
        switch node {
        case .leaf(let block):
            return block.id == id ? nil : node
        case .split(let axis, let children, let fractions):
            var newChildren: [PaneNode] = []
            var removedDirectChild = false

            for (child, fraction) in zip(children, fractions) {
                if case .leaf(let block) = child, block.id == id {
                    removedDirectChild = true
                    continue
                }
                if let kept = removing(id, from: child) {
                    newChildren.append(kept)
                } else {
                    removedDirectChild = true
                }
                _ = fraction
            }

            if newChildren.isEmpty { return nil }
            if newChildren.count == 1 { return newChildren[0] }

            if removedDirectChild {
                return .split(axis: axis, children: newChildren, fractions: equalFractions(newChildren.count))
            }
            // Removal happened deeper; child count here is unchanged, so
            // keep this container's fractions.
            return .split(axis: axis, children: newChildren, fractions: node.fractionsOrEqual(count: newChildren.count))
        }
    }

    private static func inserting(_ block: Block, at targetID: UUID, edge: PaneEdge, in node: PaneNode) -> PaneNode {
        switch node {
        case .leaf(let existing):
            guard existing.id == targetID else { return node }
            let pair =
                edge.insertsFirst
                ? [PaneNode.leaf(block), node]
                : [node, PaneNode.leaf(block)]
            return .split(axis: edge.axis, children: pair, fractions: equalFractions(2))

        case .split(let axis, let children, let fractions):
            // Parallel drop onto a direct child: join this container as an
            // equal sibling instead of nesting.
            if axis == edge.axis,
                let targetIndex = children.firstIndex(where: {
                    if case .leaf(let b) = $0 { b.id == targetID } else { false }
                })
            {
                var newChildren = children
                newChildren.insert(.leaf(block), at: edge.insertsFirst ? targetIndex : targetIndex + 1)
                return .split(axis: axis, children: newChildren, fractions: equalFractions(newChildren.count))
            }

            return .split(
                axis: axis,
                children: children.map { inserting(block, at: targetID, edge: edge, in: $0) },
                fractions: fractions
            )
        }
    }

    private static func settingBoundary(path: ArraySlice<Int>, after index: Int, to position: Double, in node: PaneNode)
        -> PaneNode
    {
        guard case .split(let axis, let children, var fractions) = node else { return node }

        if let step = path.first {
            guard children.indices.contains(step) else { return node }
            var newChildren = children
            newChildren[step] = settingBoundary(path: path.dropFirst(), after: index, to: position, in: children[step])
            return .split(axis: axis, children: newChildren, fractions: fractions)
        }

        guard fractions.indices.contains(index), fractions.indices.contains(index + 1) else { return node }
        let before = fractions.prefix(index).reduce(0, +)
        let pairSum = fractions[index] + fractions[index + 1]
        let newFirst = min(max(position - before, minimumFraction), pairSum - minimumFraction)
        fractions[index] = newFirst
        fractions[index + 1] = pairSum - newFirst
        return .split(axis: axis, children: children, fractions: fractions)
    }
}

extension TileLayout {
    static func collectFrames(_ node: PaneNode, rect: CGRect, into frames: inout [UUID: CGRect]) {
        switch node {
        case .leaf(let block):
            frames[block.id] = rect
        case .split(let axis, let children, let fractions):
            var offset: CGFloat = 0
            for (child, fraction) in zip(children, fractions) {
                let childRect: CGRect
                if axis == .horizontal {
                    childRect = CGRect(
                        x: rect.minX + rect.width * offset,
                        y: rect.minY,
                        width: rect.width * fraction,
                        height: rect.height
                    )
                } else {
                    childRect = CGRect(
                        x: rect.minX,
                        y: rect.minY + rect.height * offset,
                        width: rect.width,
                        height: rect.height * fraction
                    )
                }
                collectFrames(child, rect: childRect, into: &frames)
                offset += fraction
            }
        }
    }

    /// Child-index path from the root to the pane, or nil if absent.
    static func pathTo(_ id: UUID, in node: PaneNode) -> [Int]? {
        switch node {
        case .leaf(let block):
            return block.id == id ? [] : nil
        case .split(_, let children, _):
            for (index, child) in children.enumerated() {
                if let subPath = pathTo(id, in: child) {
                    return [index] + subPath
                }
            }
            return nil
        }
    }

    static func node(at path: ArraySlice<Int>, in node: PaneNode) -> PaneNode? {
        guard let step = path.first else { return node }
        guard case .split(_, let children, _) = node, children.indices.contains(step) else { return nil }
        return Self.node(at: path.dropFirst(), in: children[step])
    }

    static func equalizing(_ node: PaneNode) -> PaneNode {
        switch node {
        case .leaf:
            return node
        case .split(let axis, let children, _):
            return .split(
                axis: axis,
                children: children.map(equalizing),
                fractions: Array(repeating: 1.0 / Double(max(children.count, 1)), count: children.count)
            )
        }
    }
}

extension PaneNode {
    fileprivate func fractionsOrEqual(count: Int) -> [Double] {
        if case .split(_, _, let fractions) = self, fractions.count == count {
            return fractions
        }
        return Array(repeating: 1.0 / Double(max(count, 1)), count: count)
    }
}
