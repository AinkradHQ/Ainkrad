import Foundation
import Testing

@testable import Ainkrad

@Suite("WorkspaceManager")
@MainActor
struct WorkspaceManagerTests {

    @Test("starts with exactly one workspace — the main one, named Main, active")
    func startsWithOneActiveWorkspace() {
        let manager = WorkspaceManager()
        #expect(manager.workspaces.count == 1)
        #expect(manager.activeWorkspace.id == manager.workspaces[0].id)
        #expect(manager.workspaces[0].isMain)
        #expect(manager.workspaces[0].name == "Main")
    }

    @Test("createWorkspace adds a named, non-main workspace and switches to it")
    func createWorkspaceSwitchesToIt() {
        let manager = WorkspaceManager()
        let original = manager.activeWorkspace

        let created = manager.createWorkspace()

        #expect(manager.workspaces.count == 2)
        #expect(manager.activeWorkspace.id == created.id)
        #expect(created.id != original.id)
        #expect(!created.isMain)
        #expect(created.name == "Workspace 2")
    }

    @Test("deleteWorkspace removes a non-main workspace")
    func deleteRemovesNonMainWorkspace() {
        let manager = WorkspaceManager()
        let created = manager.createWorkspace()

        manager.deleteWorkspace(created.id)

        #expect(manager.workspaces.count == 1)
        #expect(manager.workspaces[0].isMain)
    }

    @Test("the main workspace cannot be deleted")
    func mainWorkspaceCannotBeDeleted() {
        let manager = WorkspaceManager()
        let main = manager.workspaces[0]

        manager.deleteWorkspace(main.id)

        #expect(manager.workspaces.count == 1)
    }

    @Test("deleting the active workspace falls back to the main workspace")
    func deletingActiveFallsBackToMain() {
        let manager = WorkspaceManager()
        let created = manager.createWorkspace()
        #expect(manager.activeWorkspace.id == created.id)

        manager.deleteWorkspace(created.id)

        #expect(manager.activeWorkspace.isMain)
    }

    @Test("deleting the active workspace finds main by flag, not by position")
    func deletingActiveFindsMainWhereverItSits() {
        let manager = WorkspaceManager()
        let main = manager.workspaces[0]
        _ = manager.createWorkspace()
        let third = manager.createWorkspace()
        manager.moveWorkspace(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(manager.workspaces.last?.id == main.id)

        manager.deleteWorkspace(third.id)

        #expect(manager.activeWorkspace.id == main.id)
    }

    @Test("a restore without a main workspace re-creates one, and the active workspace still resolves")
    func restoreWithoutMainKeepsActiveValid() {
        let source = WorkspaceManager()
        let extra = source.createWorkspace()
        var snapshot = source.snapshot()
        snapshot.workspaces = snapshot.workspaces.filter { !$0.isMain }
        snapshot.activeWorkspaceIndex = 0

        let manager = WorkspaceManager()
        manager.restore(from: snapshot)

        #expect(manager.workspaces.map(\.isMain) == [true, false])
        #expect(manager.workspaces[1].name == extra.name)
        // The re-created main is inserted first, so index 0 now names it.
        #expect(manager.activeWorkspace.isMain)
    }

    @Test("deleting an inactive workspace keeps the active one active")
    func deletingInactiveKeepsActive() {
        let manager = WorkspaceManager()
        let second = manager.createWorkspace()
        let third = manager.createWorkspace()

        manager.deleteWorkspace(second.id)

        #expect(manager.activeWorkspace.id == third.id)
    }

    @Test("moveWorkspace reorders, and index-based switching follows the new order")
    func moveWorkspaceReorders() {
        let manager = WorkspaceManager()
        let second = manager.createWorkspace()
        let third = manager.createWorkspace()
        let mainID = manager.workspaces[0].id

        // Move the third workspace to position 1 (right after main).
        manager.moveWorkspace(fromOffsets: IndexSet(integer: 2), toOffset: 1)

        #expect(manager.workspaces.map { $0.id } == [mainID, third.id, second.id])
        manager.switchToWorkspace(at: 1)
        #expect(manager.activeWorkspace.id == third.id)
    }

    @Test("a workspace can be renamed")
    func workspaceCanBeRenamed() {
        let manager = WorkspaceManager()
        let created = manager.createWorkspace()

        created.name = "Research"

        #expect(manager.workspaces[1].name == "Research")
    }

    @Test("each workspace has its own independent TileLayout")
    func workspacesHaveIndependentLayouts() {
        let manager = WorkspaceManager()
        let first = manager.activeWorkspace
        first.tileLayout.openApp("terminal")

        let second = manager.createWorkspace()

        #expect(!first.tileLayout.isEmpty)
        #expect(second.tileLayout.isEmpty)
    }

    @Test("moveApp re-homes a pane from one workspace to another, preserving its block id")
    func moveAppBetweenWorkspaces() {
        let manager = WorkspaceManager()
        let source = manager.activeWorkspace
        let block = source.tileLayout.openApp("terminal")
        let destination = manager.createWorkspace()

        manager.moveApp(block.id, from: source.id, to: destination.id)

        #expect(source.tileLayout.isEmpty)
        #expect(destination.tileLayout.blocks.map(\.id) == [block.id])
        #expect(destination.tileLayout.appIDs == ["terminal"])
    }

    @Test("moveApp is a no-op when source == destination or the block is missing")
    func moveAppNoOps() {
        let manager = WorkspaceManager()
        let source = manager.activeWorkspace
        let block = source.tileLayout.openApp("terminal")

        manager.moveApp(block.id, from: source.id, to: source.id)
        #expect(source.tileLayout.appIDs == ["terminal"])

        let destination = manager.createWorkspace()
        manager.moveApp(UUID(), from: source.id, to: destination.id)
        #expect(source.tileLayout.appIDs == ["terminal"])
        #expect(destination.tileLayout.isEmpty)
    }

    @Test("switchTo an existing workspace id makes it active")
    func switchToExistingWorkspace() {
        let manager = WorkspaceManager()
        let first = manager.activeWorkspace
        let second = manager.createWorkspace()

        manager.switchTo(first.id)

        #expect(manager.activeWorkspace.id == first.id)
        _ = second
    }

    @Test("switchTo a nonexistent id is a no-op")
    func switchToNonexistentIdIsNoOp() {
        let manager = WorkspaceManager()
        let active = manager.activeWorkspace

        manager.switchTo(UUID())

        #expect(manager.activeWorkspace.id == active.id)
    }

    @Test("switchToWorkspace(at:) jumps directly to the Nth workspace (⌘1-⌘9 mapping)")
    func switchToWorkspaceAtIndex() {
        let manager = WorkspaceManager()
        let first = manager.activeWorkspace
        let second = manager.createWorkspace()
        let third = manager.createWorkspace()

        manager.switchToWorkspace(at: 0)
        #expect(manager.activeWorkspace.id == first.id)

        manager.switchToWorkspace(at: 1)
        #expect(manager.activeWorkspace.id == second.id)

        manager.switchToWorkspace(at: 2)
        #expect(manager.activeWorkspace.id == third.id)
    }

    @Test("switchToWorkspace(at:) with an out-of-range index is a no-op")
    func switchToWorkspaceAtOutOfRangeIndexIsNoOp() {
        let manager = WorkspaceManager()
        let active = manager.activeWorkspace

        manager.switchToWorkspace(at: 8)

        #expect(manager.activeWorkspace.id == active.id)
    }

    @Test("switchToNextWorkspace advances in order and wraps around to the first")
    func nextWorkspaceCyclesForward() {
        let manager = WorkspaceManager()
        let main = manager.workspaces[0]
        let second = manager.createWorkspace()
        let third = manager.createWorkspace()
        manager.switchTo(main.id)

        manager.switchToNextWorkspace()
        #expect(manager.activeWorkspace.id == second.id)

        manager.switchToNextWorkspace()
        #expect(manager.activeWorkspace.id == third.id)

        // Past the last one wraps back to the first.
        manager.switchToNextWorkspace()
        #expect(manager.activeWorkspace.id == main.id)
    }

    @Test("switchToPreviousWorkspace steps back in order and wraps around to the last")
    func previousWorkspaceCyclesBackward() {
        let manager = WorkspaceManager()
        let main = manager.workspaces[0]
        let second = manager.createWorkspace()
        let third = manager.createWorkspace()
        manager.switchTo(main.id)

        // Before the first wraps to the last.
        manager.switchToPreviousWorkspace()
        #expect(manager.activeWorkspace.id == third.id)

        manager.switchToPreviousWorkspace()
        #expect(manager.activeWorkspace.id == second.id)

        manager.switchToPreviousWorkspace()
        #expect(manager.activeWorkspace.id == main.id)
    }

    @Test("pruneApps drops panes whose app is no longer registered")
    func pruneRemovesUnknownApps() {
        let manager = WorkspaceManager()
        let ws = manager.createWorkspace()
        _ = ws.tileLayout.openApp("terminal")
        _ = ws.tileLayout.openApp("settings")  // no longer a registered app
        _ = ws.tileLayout.openApp("terminal")

        manager.pruneApps(keeping: ["terminal"])

        #expect(ws.tileLayout.appIDs == ["terminal", "terminal"])
    }

    @Test("pruneApps empties a workspace whose apps are all unregistered")
    func pruneEmptiesFullyUnknownWorkspace() {
        let manager = WorkspaceManager()
        let ws = manager.createWorkspace()
        _ = ws.tileLayout.openApp("settings")

        manager.pruneApps(keeping: ["terminal"])

        #expect(ws.tileLayout.isEmpty)
    }

    @Test("cycling is a no-op with only one workspace")
    func cyclingWithSingleWorkspaceIsNoOp() {
        let manager = WorkspaceManager()
        let only = manager.activeWorkspace

        manager.switchToNextWorkspace()
        #expect(manager.activeWorkspace.id == only.id)

        manager.switchToPreviousWorkspace()
        #expect(manager.activeWorkspace.id == only.id)
    }
}
