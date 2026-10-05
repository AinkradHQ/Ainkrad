import Foundation
import SwiftUI

/// A workspace row's drop target: dragging another workspace row reorders the
/// list; dropping an app dragged from the detail pane moves that app here.
struct WorkspaceRowDropDelegate: DropDelegate {
    let target: UUID
    @Binding var draggedWorkspace: UUID?
    @Binding var draggedApp: WorkspaceOverviewView.DraggedApp?
    let manager: WorkspaceManager

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedWorkspace, dragged != target,
            let from = manager.workspaces.firstIndex(where: { $0.id == dragged }),
            let to = manager.workspaces.firstIndex(where: { $0.id == target })
        else { return }
        manager.moveWorkspace(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        if let app = draggedApp, app.sourceWorkspaceID != target, acceptsApps {
            manager.moveApp(app.blockID, from: app.sourceWorkspaceID, to: target)
        }
        draggedWorkspace = nil
        draggedApp = nil
        return true
    }

    /// The home workspace stays empty by design — opening an app from it spawns
    /// a new workspace instead — so it must not accept a pane dropped on it
    /// either. Enforced here and not only by hiding the highlight, because a
    /// highlight is a hint and this is a rule.
    private var acceptsApps: Bool {
        manager.workspaces.first { $0.id == target }?.isMain == false
    }
}
