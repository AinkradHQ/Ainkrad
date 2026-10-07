import Foundation
import Observation

/// Multiple workspaces, each with its own independent tile layout. The
/// first workspace is the **main** one — the permanent home island (see
/// Workspace). Switching: `⌘1`-`⌘9` by position, `⌘⇧N` create, clickable
/// HUD diamonds, and the `⌥Tab` Workspace Overview. The whole layout
/// state persists as JSON through `SettingsStore` and restores at launch
/// (running panel state is ephemeral by design).
@MainActor
@Observable
final class WorkspaceManager {
    private(set) var workspaces: [Workspace]
    private(set) var activeWorkspaceID: UUID
    private var createdCount = 1
    /// Persistence hook, assigned at bootstrap and bubbled into every
    /// workspace's layout so any structural change saves.
    var onStateChange: (() -> Void)? {
        didSet {
            workspaces.forEach { $0.tileLayout.onStructuralChange = onStateChange }
        }
    }

    init() {
        let main = Workspace(name: "Main", isMain: true)
        self.workspaces = [main]
        self.activeWorkspaceID = main.id
    }

    /// `activeWorkspaceID` only ever names a workspace in `workspaces`: it is
    /// set from one, and deleting the active workspace moves it to main first.
    var activeWorkspace: Workspace {
        guard let active = workspaces.first(where: { $0.id == activeWorkspaceID }) else {
            preconditionFailure("activeWorkspaceID names no workspace")
        }
        return active
    }

    /// The permanent home workspace. There is always exactly one: `init`
    /// creates it, `deleteWorkspace` refuses it and `restore` re-creates it.
    private var mainWorkspace: Workspace {
        guard let main = workspaces.first(where: { $0.isMain }) else {
            preconditionFailure("the main workspace is missing")
        }
        return main
    }

    @discardableResult
    func createWorkspace() -> Workspace {
        createdCount += 1
        let workspace = Workspace(name: "Workspace \(createdCount)")
        workspace.tileLayout.onStructuralChange = onStateChange
        workspaces.append(workspace)
        activeWorkspaceID = workspace.id
        onStateChange?()
        return workspace
    }

    /// The main workspace is permanent; deleting the active workspace
    /// falls back to main.
    func deleteWorkspace(_ id: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == id }), !workspace.isMain else { return }
        workspaces.removeAll { $0.id == id }
        if activeWorkspaceID == id {
            activeWorkspaceID = mainWorkspace.id
        }
        onStateChange?()
    }

    func moveWorkspace(fromOffsets source: IndexSet, toOffset destination: Int) {
        workspaces.move(fromOffsets: source, toOffset: destination)
        onStateChange?()
    }

    /// Moves an open app (pane) from one workspace to another, preserving its
    /// block identity. Running pane state is ephemeral by design, so the app
    /// re-renders in its new home. No-op if source == destination or the block
    /// isn't found.
    func moveApp(_ blockID: UUID, from sourceID: UUID, to destinationID: UUID) {
        guard sourceID != destinationID,
            let source = workspaces.first(where: { $0.id == sourceID }),
            let destination = workspaces.first(where: { $0.id == destinationID }),
            let block = source.tileLayout.blocks.first(where: { $0.id == blockID })
        else { return }
        source.tileLayout.close(blockID)
        destination.tileLayout.adopt(block)
        onStateChange?()
    }

    /// Opens a second instance of an app in another workspace (copy, not move).
    func duplicateApp(_ appID: String, to destinationID: UUID) {
        guard let destination = workspaces.first(where: { $0.id == destinationID }) else { return }
        destination.tileLayout.openApp(appID)
        onStateChange?()
    }

    func switchTo(_ id: UUID) {
        guard workspaces.contains(where: { $0.id == id }) else { return }
        activeWorkspaceID = id
        onStateChange?()
    }

    /// `index` is 0-based; `⌘1` maps to index 0, `⌘9` to index 8.
    func switchToWorkspace(at index: Int) {
        guard workspaces.indices.contains(index) else { return }
        activeWorkspaceID = workspaces[index].id
        onStateChange?()
    }

    /// Cycles to the next workspace in order, wrapping past the last back
    /// to the first (`⌘⌥→`). A no-op with a single workspace.
    func switchToNextWorkspace() { cycleActiveWorkspace(by: 1) }

    /// Cycles to the previous workspace in order, wrapping before the first
    /// around to the last (`⌘⌥←`). A no-op with a single workspace.
    func switchToPreviousWorkspace() { cycleActiveWorkspace(by: -1) }

    private func cycleActiveWorkspace(by delta: Int) {
        let count = workspaces.count
        guard count > 1,
            let current = workspaces.firstIndex(where: { $0.id == activeWorkspaceID })
        else { return }
        let next = ((current + delta) % count + count) % count
        activeWorkspaceID = workspaces[next].id
        onStateChange?()
    }

    /// True when this app has a tiled pane in ANY workspace, not just the
    /// active one — a block on an inactive workspace is still a live shell.
    ///
    /// Deliberately named `isAppTiled`, not `isAppOpen`: an `.overlay`-
    /// presentation app is open without ever having a block here (it lives in
    /// `AppEnvironment.presentedOverlayAppID`, which this type does not and
    /// should not know about). "Is this app open?" is `AppEnvironment.isAppOpen`.
    func isAppTiled(_ appID: String) -> Bool {
        workspaces.contains { $0.tileLayout.blocks.contains { $0.appID == appID } }
    }

    /// Drops any open pane whose app id is not in `validIDs` — used at launch
    /// to clean a restored layout of apps that no longer exist (e.g. Settings,
    /// once it became an overlay instead of a tiled Block).
    func pruneApps(keeping validIDs: Set<String>) {
        for workspace in workspaces {
            for block in workspace.tileLayout.blocks where !validIDs.contains(block.appID) {
                workspace.tileLayout.close(block.id)
            }
        }
    }

    // MARK: - Persistence

    /// Explicit save trigger for mutations that don't flow through the
    /// structural-change hooks (e.g. renames, view-mode toggles).
    func persist() {
        onStateChange?()
    }

    func snapshot() -> LayoutStateSnapshot {
        LayoutStateSnapshot(
            workspaces: workspaces.map { $0.snapshot() },
            activeWorkspaceIndex: workspaces.firstIndex(where: { $0.id == activeWorkspaceID }) ?? 0
        )
    }

    /// Rebuilds the whole state from a snapshot. The first main-flagged
    /// workspace becomes the home island; a missing main is re-created.
    func restore(from snapshot: LayoutStateSnapshot) {
        guard !snapshot.workspaces.isEmpty else { return }

        var restored: [Workspace] = []
        for workspaceSnapshot in snapshot.workspaces {
            let workspace = Workspace(
                name: workspaceSnapshot.name,
                isMain: workspaceSnapshot.isMain && !restored.contains(where: { $0.isMain }),
                viewMode: workspaceSnapshot.viewMode
            )
            workspace.tileLayout.onStructuralChange = onStateChange
            if let root = workspaceSnapshot.root {
                workspace.tileLayout.apply(root)
            }
            restored.append(workspace)
        }
        if !restored.contains(where: { $0.isMain }) {
            let main = Workspace(name: "Main", isMain: true)
            main.tileLayout.onStructuralChange = onStateChange
            restored.insert(main, at: 0)
        }

        workspaces = restored
        createdCount = max(restored.count, 1)
        let activeIndex = min(max(snapshot.activeWorkspaceIndex, 0), restored.count - 1)
        activeWorkspaceID = restored[activeIndex].id
    }
}
