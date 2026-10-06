import AinkradAppKit

/// How far an arrow key moves the Launcher's selection, or `nil` when the key
/// is not the Launcher's to take (left/right in the list belong to the caret).
///
/// In the grid, up/down step a whole row of `columns` and left/right step one
/// cell; in the list, up/down step one row.
func launcherArrowStep(_ arrow: AinkradArrow, isGrid: Bool, columns: Int) -> Int? {
    switch arrow {
    case .down: isGrid ? columns : 1
    case .up: isGrid ? -columns : -1
    case .right: isGrid ? 1 : nil
    case .left: isGrid ? -1 : nil
    @unknown default: nil
    }
}

/// The selection after moving `delta` through `count` results, wrapping at
/// both ends. An empty result list leaves the selection where it is.
func launcherSelection(_ index: Int, movedBy delta: Int, count: Int) -> Int {
    guard count > 0 else { return index }
    return (index + delta + count) % count
}
