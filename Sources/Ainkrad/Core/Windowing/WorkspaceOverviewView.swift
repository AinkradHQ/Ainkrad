import AinkradAppKit
import AinkradHostRuntime
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The ⌥Tab Workspace Overview — a master–detail workspace manager in the HUD
/// language. Left: the workspace list (mini layout previews, rename, reorder,
/// delete) that doubles as drop targets. Right: the selected workspace's apps,
/// each openable, duplicable, closable, and draggable onto a workspace in the
/// list to move it there.
struct WorkspaceOverviewView: View {
    @Environment(AppEnvironment.self) var environment
    @Environment(\.ainkradSkin) var skin
    let onDismiss: () -> Void

    @State var selectedWorkspaceID: UUID?
    @State private var renamingWorkspaceID: UUID?
    @State private var renameDraft = ""
    @State private var draggedWorkspaceID: UUID?
    @State var draggedApp: DraggedApp?
    @State private var pendingDeletion: Workspace?
    /// The app row whose "duplicate to…" HUD popover is open, if any.
    @State var duplicateMenuBlockID: UUID?
    @FocusState private var focus: FocusTarget?

    /// A pane being dragged from the detail pane onto a workspace (to move it).
    struct DraggedApp: Equatable {
        let blockID: UUID
        let sourceWorkspaceID: UUID
    }

    enum FocusTarget: Hashable {
        case panel
        case rename(UUID)
    }

    var manager: WorkspaceManager { environment.workspaceManager }

    /// Colours come from `hostSkin`, which carries the user's custom accent;
    /// every scalar comes from the environment's skin.
    var tokens: AinkradSkin { environment.themeManager.hostSkin }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                skin.color(.palette("black", skin.chrome.overlay.backdropOpacity))
                    .ignoresSafeArea()
                    .onTapGesture { onDismiss() }

                panel
                    .frame(width: min(max(820, geo.size.width * 0.66), 1060))
                    // The panel takes its CONTENT's height, clamped to what the
                    // window can show.
                    //
                    // It used to take a fixed share of the window whatever it
                    // contained, so three workspaces and three apps left about a
                    // third of it empty — and the empty part was below the
                    // content, which reads as a panel that failed to fill rather
                    // than as deliberate space.
                    //
                    // Computed rather than `fixedSize`, which was the first
                    // attempt: `fixedSize` refuses to shrink, so on a window
                    // shorter than the content the panel overflowed instead of
                    // adapting. Taking the minimum of the two lets the preview's
                    // height range absorb the difference.
                    .frame(height: panelHeight(in: geo.size))
                    .offset(y: -24)
                    // Scoped to the panel: the kit dialog dims and centres
                    // within the view it is attached to.
                    .ainkradConfirmDialog(
                        isPresented: Binding(
                            get: { pendingDeletion != nil },
                            set: { if !$0 { pendingDeletion = nil } }),
                        title: "Delete “\(pendingDeletion?.name ?? "")”?",
                        message: Self.deletionMessage(appCount: pendingDeletion?.tileLayout.appIDs.count ?? 0),
                        confirmTitle: "Delete",
                        isDestructive: true
                    ) {
                        if let pendingDeletion { confirmDeletion(pendingDeletion) }
                    }
            }
        }
        .onAppear {
            selectedWorkspaceID = manager.activeWorkspaceID
            focus = .panel
        }
    }

    // MARK: - Panel height

    /// What the panel would like to be: its chrome, plus the taller of the two
    /// columns.
    private var idealPanelHeight: CGFloat {
        Self.panelChromeHeight + max(workspaceListHeight, idealDetailHeight)
    }

    /// The detail column's height, which deliberately does NOT depend on the
    /// selection.
    ///
    /// It used to: an empty workspace produced a 382pt panel and a filled one
    /// 624pt, so the panel changed size as the selection moved down the list.
    /// Each state was individually well-fitted and the transitions between them
    /// were awful, which is the wrong trade on a screen that exists for moving
    /// between states. `WorkspaceOverviewDetail` now fits every state into one
    /// height, giving the slack to the preview.
    private var idealDetailHeight: CGFloat { Self.detailHeight }

    /// The height the panel actually gets: what it wants, or what the window can
    /// show, whichever is smaller.
    func panelHeight(in size: CGSize) -> CGFloat {
        min(idealPanelHeight, Self.ceiling(forWindowHeight: size.height))
    }

    static func ceiling(forWindowHeight height: CGFloat) -> CGFloat {
        min(max(420, height * 0.9), maximumPanelHeight)
    }

    /// What the delete confirmation says about a workspace that still has apps.
    static func deletionMessage(appCount: Int) -> String {
        let apps = "\(appCount) app\(appCount == 1 ? "" : "s")"
        let sessions = appCount == 1 ? "its session" : "their sessions"
        return "\(apps) still running here — \(sessions) will end."
    }

    // MARK: - Panel

    /// Header, the two columns and the footer, with no rules between them: the
    /// gaps and the column backgrounds carry the grouping (design bar — no
    /// separator lines).
    private var panel: some View {
        let store = environment.generalSettingsStore
        return VStack(alignment: .leading, spacing: 0) {
            header
            // `.top`, because the two columns no longer have the same height:
            // whichever is shorter must sit at the top of the row rather than
            // float in the middle of it.
            HStack(alignment: .top, spacing: 0) {
                workspaceList
                    .frame(width: skin.size.s268, height: workspaceListHeight)
                detailPane
                    .frame(maxWidth: .infinity)
            }
            footer
        }
        // The user's overlay opacity and blur settings, as every summoned
        // overlay reads them.
        .ainkradOverlayChrome(
            backgroundOpacity: store.overlayOpacity(in: skin),
            blurEnabled: store.overlayBlurEnabled,
            blending: .withinWindow)
        .focusable()
        .focused($focus, equals: .panel)
        .focusEffectDisabled()
        .onKeyPress(.escape) {
            if pendingDeletion != nil {
                pendingDeletion = nil
                return .handled
            }
            guard renamingWorkspaceID == nil else { return .ignored }
            onDismiss()
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard canNavigate else { return .ignored }
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard canNavigate else { return .ignored }
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.return) {
            if let pendingDeletion {
                confirmDeletion(pendingDeletion)
                return .handled
            }
            guard renamingWorkspaceID == nil else { return .ignored }
            activateSelection()
            return .handled
        }
        .onKeyPress(.deleteForward) {
            guard canNavigate, let ws = selectedWorkspace, !ws.isMain else { return .ignored }
            requestDeletion(ws)
            return .handled
        }
    }

    private var canNavigate: Bool { renamingWorkspaceID == nil && pendingDeletion == nil }

    private var header: some View {
        HStack(spacing: skin.spacing.md) {
            ChevronMark()
                .fill(tokens.color(\.accentSecondary))
                .frame(width: skin.size.s16, height: skin.size.s14)
                .shadow(color: tokens.color(\.accentSecondary).opacity(skin.opacity.o90), radius: skin.size.s6)
            Text(skin.labelCased("Workspaces"))
                .font(AinkradFont.display(13, weight: .semibold))
                .kerning(skin.labelKerning(4))
                .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o90))
            Spacer()
            Text("\(manager.workspaces.count)")
                .font(AinkradFont.mono(11, weight: .medium))
                .foregroundStyle(tokens.color(\.accentSecondary).opacity(skin.opacity.o80))
        }
        .padding(.horizontal, skin.size.s18)
        .frame(height: skin.size.s52)
    }

    // MARK: - Workspace list (master)

    /// Exactly the height the workspace rows need, capped so a long list scrolls
    /// rather than stretching the panel past its ceiling.
    ///
    /// Computable because every part of a row is fixed or single-line: the
    /// preview is framed at 36pt and the name, count and shortcut are all
    /// `lineLimit(1)`, so a row is always `Self.rowHeight`. That determinism is
    /// what a hugging panel needs — a `ScrollView` left to itself always claims
    /// every point offered, which is what stopped the panel shrinking.
    private var workspaceListHeight: CGFloat {
        let count = CGFloat(manager.workspaces.count)
        let rows = count * Self.rowHeight + max(count - 1, 0) * Self.rowSpacing
        return min(
            rows + Self.newWorkspaceButtonHeight + Self.rowSpacing + Self.listPadding * 2,
            Self.maximumListHeight)
    }

    private static let rowHeight: CGFloat = 50
    private static let rowSpacing: CGFloat = 4
    private static let newWorkspaceButtonHeight: CGFloat = 38
    private static let listPadding: CGFloat = 10
    private static let maximumListHeight: CGFloat = 520

    /// Header and footer — everything the panel spends on itself, outside the
    /// two columns. (106 while a 1pt rule sat under the header.)
    static let panelChromeHeight: CGFloat = 105
    /// The panel's own ceiling. Must clear the tallest content it can hold, or a
    /// busy workspace overflows the chrome instead of scrolling inside it —
    /// asserted in `WorkspaceOverviewLayoutTests`.
    static let maximumPanelHeight: CGFloat = 860

    private var workspaceList: some View {
        ScrollView {
            VStack(spacing: Self.rowSpacing) {
                ForEach(Array(manager.workspaces.enumerated()), id: \.element.id) { index, workspace in
                    workspaceRow(workspace, index: index)
                }
                newWorkspaceRow
            }
            .padding(Self.listPadding)
        }
    }

    private func workspaceRow(_ workspace: Workspace, index: Int) -> some View {
        // An app can be dropped on any workspace except the one it came from —
        // and except the home workspace, which by design stays empty (opening an
        // app from it spawns a new workspace instead). Offering it as a target
        // let a pane be moved somewhere the rest of the app says panes don't go.
        let isDropTarget =
            draggedApp != nil
            && draggedApp?.sourceWorkspaceID != workspace.id
            && !workspace.isMain

        return WorkspaceListRow(
            workspace: workspace,
            registry: environment.registry,
            index: index,
            isActive: workspace.id == manager.activeWorkspaceID,
            isSelected: workspace.id == selectedWorkspaceID,
            isDropTarget: isDropTarget,
            isRenaming: renamingWorkspaceID == workspace.id,
            renameDraft: $renameDraft,
            renameFocus: $focus,
            onSelect: { selectedWorkspaceID = workspace.id },
            onActivate: { activate(workspace) },
            onBeginRename: { beginRename(workspace) },
            onCommitRename: { commitRename(workspace) },
            onCancelRename: { cancelRename() },
            onRequestDeletion: { requestDeletion(workspace) },
            onBeginDrag: {
                draggedWorkspaceID = workspace.id
                return NSItemProvider(object: workspace.id.uuidString as NSString)
            },
            dropDelegate: WorkspaceRowDropDelegate(
                target: workspace.id,
                draggedWorkspace: $draggedWorkspaceID,
                draggedApp: $draggedApp,
                manager: manager
            )
        )
    }

    /// The last row of the list: a kit row that creates a workspace and selects
    /// it, wearing the shortcut that does the same from anywhere.
    private var newWorkspaceRow: some View {
        AinkradListRow(
            onTap: {
                let workspace = manager.createWorkspace()
                selectedWorkspaceID = workspace.id
            },
            leading: {
                Image(systemName: "plus")
                    .font(skin.font(AinkradFontToken(sizeKey: "t12", weight: "medium", scaled: false)))
                    .foregroundStyle(tokens.color(\.accentSecondary))
            },
            title: "New Workspace",
            trailing: {
                Text("⌘⇧N").font(AinkradFont.mono(9)).foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o30))
            }
        )
    }

    // MARK: - Footer

    /// The keyboard hints only. The mouse hints that used to share this row
    /// ("drag an app onto a workspace… double-click to rename…") were the FIRST
    /// thing to be truncated away when the panel narrowed — advice that vanishes
    /// exactly when the window is small is not advice. Every one of those actions
    /// now says what it is where it happens: the row's own tooltips, its pencil
    /// button, and its context menu.
    private var footer: some View {
        HStack(spacing: skin.size.s14) {
            Spacer()
            ForEach(Self.keyboardHints, id: \.keys) { hint in
                HStack(spacing: skin.size.s5) {
                    Text(hint.keys)
                        .font(AinkradFont.mono(10, weight: .medium))
                        .foregroundStyle(tokens.color(\.accentSecondary).opacity(skin.opacity.o80))
                        .lineLimit(1).fixedSize()
                    Text(hint.label)
                        .font(AinkradFont.mono(10))
                        .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o45))
                        .lineLimit(1).fixedSize()
                }
            }
        }
        .padding(.horizontal, skin.size.s18)
        .padding(.vertical, skin.spacing.md)
    }

    private static let keyboardHints: [(keys: String, label: String)] = [
        ("↑↓", "select"),
        ("↩", "switch"),
        ("⌦", "delete"),
        ("esc", "dismiss"),
    ]

    // MARK: - Actions

    var selectedWorkspace: Workspace? {
        manager.workspaces.first { $0.id == selectedWorkspaceID }
    }

    private func moveSelection(by delta: Int) {
        let workspaces = manager.workspaces
        guard !workspaces.isEmpty else { return }
        let current = workspaces.firstIndex { $0.id == selectedWorkspaceID } ?? 0
        let next = (current + delta + workspaces.count) % workspaces.count
        selectedWorkspaceID = workspaces[next].id
    }

    private func activateSelection() {
        guard let workspace = selectedWorkspace else { return }
        // Drop the overlay's keyboard focus before switching so the arriving
        // workspace's pane can claim it (see `PaneKeyFocusAnchor`).
        NSApp.keyWindow?.makeFirstResponder(nil)
        activate(workspace)
    }

    private func requestDeletion(_ workspace: Workspace) {
        if workspace.tileLayout.appIDs.isEmpty {
            deleteWorkspace(workspace)
        } else {
            pendingDeletion = workspace
        }
    }

    private func confirmDeletion(_ workspace: Workspace) {
        deleteWorkspace(workspace)
        pendingDeletion = nil
    }

    private func deleteWorkspace(_ workspace: Workspace) {
        let wasSelected = selectedWorkspaceID == workspace.id
        manager.deleteWorkspace(workspace.id)
        if wasSelected { selectedWorkspaceID = manager.activeWorkspaceID }
    }

    private func beginRename(_ workspace: Workspace) {
        renameDraft = workspace.name
        renamingWorkspaceID = workspace.id
        focus = .rename(workspace.id)
    }

    private func commitRename(_ workspace: Workspace) {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            workspace.name = trimmed
            manager.persist()
        }
        renamingWorkspaceID = nil
        focus = .panel
    }

    private func cancelRename() {
        renamingWorkspaceID = nil
        focus = .panel
    }
}
