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

    var body: some View {
        let tokens = environment.themeManager.tokens

        GeometryReader { geo in
            ZStack {
                Color.black.opacity(OverlayChrome.backdropOpacity)
                    .ignoresSafeArea()
                    .onTapGesture { onDismiss() }

                panel(tokens: tokens)
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
                    .overlay {
                        if let pendingDeletion {
                            ZStack {
                                ChamferShape(cut: OverlayChrome.cornerRadius)
                                    .fill(.black.opacity(0.5))
                                    .transition(.opacity)
                                DeleteWorkspaceConfirmation(
                                    workspaceName: pendingDeletion.name,
                                    appCount: pendingDeletion.tileLayout.appIDs.count,
                                    tokens: tokens,
                                    onCancel: { self.pendingDeletion = nil },
                                    onConfirm: { confirmDeletion(pendingDeletion) }
                                )
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            }
                        }
                    }
            }
        }
        .animation(.easeOut(duration: 0.16), value: pendingDeletion?.id)
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

    // MARK: - Panel

    private func panel(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(tokens: tokens)
            horizontalRule(tokens: tokens)
            // `.top`, because the two columns no longer have the same height:
            // whichever is shorter must sit at the top of the row rather than
            // float in the middle of it.
            HStack(alignment: .top, spacing: 0) {
                workspaceList(tokens: tokens)
                    .frame(width: 268, height: workspaceListHeight)
                detailPane(tokens: tokens)
                    .frame(maxWidth: .infinity)
            }
            // The divider is an OVERLAY, not a child.
            //
            // As a child it was the one thing left demanding infinite height —
            // it stretches to fill the row on purpose, which is right when the
            // row's height comes from somewhere else and fatal when the row is
            // supposed to take its content's height: one flexible child is all it
            // takes to pull the panel back up to its ceiling. An overlay fills
            // the row without having a vote in how tall it is.
            .overlay(alignment: .topLeading) {
                verticalRule(tokens: tokens)
                    .frame(width: 1)
                    .offset(x: 268)
            }
            footer(tokens: tokens)
        }
        .hudPanelChrome(tokens: tokens)
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

    private func header(tokens: DesignTokens) -> some View {
        HStack(spacing: 12) {
            ChevronMark()
                .fill(tokens.accentSecondary)
                .frame(width: 16, height: 14)
                .shadow(color: tokens.accentSecondary.opacity(0.9), radius: 6)
            Text("WORKSPACES")
                .font(AinkradFont.display(13, weight: .semibold))
                .kerning(4)
                .foregroundStyle(tokens.foreground.opacity(0.9))
            Spacer()
            Text("\(manager.workspaces.count)")
                .font(AinkradFont.mono(11, weight: .medium))
                .foregroundStyle(tokens.accentSecondary.opacity(0.8))
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
    }

    private func horizontalRule(tokens: DesignTokens) -> some View {
        LinearGradient(
            colors: [.clear, tokens.accentPrimary.opacity(0.5), .clear],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(height: 1)
    }

    private func verticalRule(tokens: DesignTokens) -> some View {
        LinearGradient(
            colors: [.clear, tokens.accentPrimary.opacity(0.35), .clear],
            startPoint: .top, endPoint: .bottom
        )
        .frame(width: 1)
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

    /// Header, footer and the rule between them — everything the panel spends on
    /// itself, outside the two columns.
    static let panelChromeHeight: CGFloat = 106
    /// The panel's own ceiling. Must clear the tallest content it can hold, or a
    /// busy workspace overflows the chrome instead of scrolling inside it —
    /// asserted in `WorkspaceOverviewLayoutTests`.
    static let maximumPanelHeight: CGFloat = 860

    private func workspaceList(tokens: DesignTokens) -> some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(Array(manager.workspaces.enumerated()), id: \.element.id) { index, workspace in
                    workspaceRow(workspace, index: index, tokens: tokens)
                }
                newWorkspaceButton(tokens: tokens)
            }
            .padding(Self.listPadding)
        }
    }

    private func workspaceRow(_ workspace: Workspace, index: Int, tokens: DesignTokens) -> some View {
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
            tokens: tokens,
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

    private func newWorkspaceButton(tokens: DesignTokens) -> some View {
        Button {
            let workspace = manager.createWorkspace()
            selectedWorkspaceID = workspace.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 12, weight: .medium)).foregroundStyle(
                    tokens.accentSecondary)
                Text("New Workspace").font(AinkradFont.display(11, weight: .medium)).foregroundStyle(
                    tokens.foreground.opacity(0.6))
                Spacer()
                Text("⌘⇧N").font(AinkradFont.mono(9)).foregroundStyle(tokens.foreground.opacity(0.3))
            }
            .padding(.horizontal, 9).padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(tokens.accentPrimary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail pane
    /// button, and its context menu.
    /// The keyboard hints only. The mouse hints that used to share this row
    /// ("drag an app onto a workspace… double-click to rename…") were the FIRST
    /// thing to be truncated away when the panel narrowed — advice that vanishes
    /// exactly when the window is small is not advice. Every one of those actions
    /// now says what it is where it happens: the row's own tooltips, its pencil
    private func footer(tokens: DesignTokens) -> some View {
        HStack(spacing: 14) {
            Spacer()
            ForEach(Self.keyboardHints, id: \.keys) { hint in
                HStack(spacing: 5) {
                    Text(hint.keys)
                        .font(AinkradFont.mono(10, weight: .medium))
                        .foregroundStyle(tokens.accentSecondary.opacity(0.8))
                        .lineLimit(1).fixedSize()
                    Text(hint.label)
                        .font(AinkradFont.mono(10))
                        .foregroundStyle(tokens.foreground.opacity(0.45))
                        .lineLimit(1).fixedSize()
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
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
