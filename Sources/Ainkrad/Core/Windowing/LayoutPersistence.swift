import Foundation
import AinkradHostRuntime

/// A serializable pane tree. A node is a leaf (`appID` set) or a split
/// (`axis`/`fractions`/`children` set). Panel identity is NOT persisted —
/// restore mints fresh instances; running state (e.g. a terminal session)
/// is intentionally ephemeral.
struct PaneSnapshot: Codable, Equatable {
    var appID: String?
    /// The leaf's user-given tab name, when it has one. Optional so layouts
    /// written before renaming existed still decode.
    var title: String?
    var axis: String?
    var fractions: [Double]?
    var children: [PaneSnapshot]?

    init?(node: PaneNode?) {
        guard let node else { return nil }
        switch node {
        case .leaf(let block):
            appID = block.appID
            title = block.title
        case .split(let axis, let children, let fractions):
            self.axis = axis == .horizontal ? "h" : "v"
            self.fractions = fractions
            self.children = children.compactMap { PaneSnapshot(node: $0) }
        }
    }

    func makeNode() -> PaneNode? {
        if let appID {
            return .leaf(Block(appID: appID, title: title))
        }
        guard let axis, let children, let fractions,
              children.count == fractions.count, !children.isEmpty else { return nil }
        let nodes = children.compactMap { $0.makeNode() }
        guard nodes.count == children.count else { return nil }
        if nodes.count == 1 { return nodes[0] }
        return .split(axis: axis == "h" ? .horizontal : .vertical, children: nodes, fractions: fractions)
    }
}

struct WorkspaceSnapshot: Codable, Equatable {
    var name: String
    var isMain: Bool
    var viewMode: WorkspaceViewMode
    var root: PaneSnapshot?
}

/// The whole persisted layout state, stored through SettingsStore and
/// restored at launch.
struct LayoutStateSnapshot: PersistableDocument {
    static let documentID = "workspace-layout"

    var workspaces: [WorkspaceSnapshot]
    var activeWorkspaceIndex: Int

    /// True when `name` is still the auto-generated "Workspace <n>" that
    /// `WorkspaceManager.createWorkspace()` mints — i.e. the user opened a
    /// workspace but never named it. Naming one is the signal that it is
    /// worth keeping across launches; an unnamed one was scratch space.
    static func isAutoNamed(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("Workspace ") else { return false }
        let suffix = trimmed.dropFirst("Workspace ".count)
        return !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
    }

    /// The snapshot as it should be applied at launch.
    ///
    /// Three things happen here, all so that opening the app never resumes
    /// the last session on the user's behalf:
    ///
    /// 1. Workspaces the user never named are dropped — main is always kept,
    ///    regardless of its name.
    /// 2. Pane trees are dropped unless `restoringPanes` is true
    ///    (Settings → General → "Restore layout on launch", default off), so
    ///    no app starts itself.
    /// 3. The active workspace is forced to main, so a launch always lands on
    ///    the home island rather than wherever the last session left off.
    ///
    /// This returns a value; the PERSISTED document is left untouched, so
    /// turning pane restore back on still finds the last saved layout.
    func launchState(restoringPanes: Bool) -> LayoutStateSnapshot {
        let kept = workspaces
            .filter { $0.isMain || !Self.isAutoNamed($0.name) }
            .map { workspace in
                WorkspaceSnapshot(
                    name: workspace.name,
                    isMain: workspace.isMain,
                    viewMode: workspace.viewMode,
                    root: restoringPanes ? workspace.root : nil
                )
            }
        return LayoutStateSnapshot(
            workspaces: kept,
            activeWorkspaceIndex: kept.firstIndex(where: { $0.isMain }) ?? 0
        )
    }
}

extension TileLayout {
    func snapshot() -> PaneSnapshot? {
        PaneSnapshot(node: root)
    }

    /// Replaces this layout's tree from a snapshot (persistence restore).
    func apply(_ snapshot: PaneSnapshot) {
        replaceRoot(snapshot.makeNode())
    }
}

extension Workspace {
    func snapshot() -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            name: name,
            isMain: isMain,
            viewMode: viewMode,
            root: tileLayout.snapshot()
        )
    }
}
