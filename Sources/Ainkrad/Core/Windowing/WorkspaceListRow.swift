import AinkradAppKit
import AinkradHostRuntime
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// One row in the Workspace Overview's workspace list: layout thumbnail, name,
/// what's in it, its ⌘N shortcut, and its row actions.
///
/// A real view rather than a function on the overview, for two reasons: hover
/// state needs somewhere to live, and the overview was past 688 lines.
struct WorkspaceListRow: View {
    let workspace: Workspace
    let registry: BuiltInAppRegistry
    /// Zero-based position, for the ⌘N shortcut label.
    let index: Int
    let isActive: Bool
    let isSelected: Bool
    /// True while an app is being dragged that this row would accept.
    let isDropTarget: Bool
    let isRenaming: Bool
    let tokens: DesignTokens
    @Binding var renameDraft: String
    let renameFocus: FocusState<WorkspaceOverviewView.FocusTarget?>.Binding
    let onSelect: () -> Void
    let onActivate: () -> Void
    let onBeginRename: () -> Void
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    let onRequestDeletion: () -> Void
    let onBeginDrag: () -> NSItemProvider
    let dropDelegate: WorkspaceRowDropDelegate

    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @State private var hovering = false

    private var appCount: Int { workspace.tileLayout.appIDs.count }

    var body: some View {
        HStack(spacing: 10) {
            // The selection marker: a solid accent bar down the leading edge.
            // Selected and active used to be a 14%-opacity wash against a
            // 6%-opacity wash — two nearly identical tints doing the work of
            // telling you where you are versus where you're looking. A bar and a
            // badge are different KINDS of mark, so they can't be confused.
            Capsule()
                .fill(isSelected ? tokens.accentSecondary : .clear)
                .frame(width: 2.5)
                .frame(maxHeight: .infinity)

            // The same preview the detail pane features, at row size — so a row
            // shows what is in the workspace, not just how many rectangles it
            // has. Two workspaces holding two side-by-side panes used to be
            // pixel-identical here.
            WorkspaceLayoutPreview(
                workspace: workspace,
                registry: registry,
                tokens: tokens,
                style: .thumbnail
            )
            .frame(width: 50, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                nameLine
                subtitleLine
            }

            Spacer(minLength: 4)

            trailingControls
        }
        .padding(.leading, 6)
        .padding(.trailing, 9)
        .padding(.vertical, 7)
        .overlay(alignment: .trailing) { hoverActions }
        .background(rowBackground)
        .overlay(
            ChamferShape(cut: AinkradRadius.md)
                .strokeBorder(borderColor, lineWidth: isDropTarget ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // Single tap fires IMMEDIATELY; the double-tap runs alongside it as a
        // SIMULTANEOUS gesture. Declaring `.onTapGesture(count: 2)` next to a
        // single-tap handler — which is what this row used to do — makes SwiftUI
        // wait out the double-click interval before delivering the single tap,
        // so selecting a workspace appeared to take a second. It wasn't slow; it
        // was waiting for permission to happen.
        //
        // This is the pattern `FileRowView` already uses for the same reason.
        .onTapGesture { onSelect() }
        // Double-click SWITCHES, it does not rename.
        //
        // Switching is what this screen is for, and on this platform
        // double-click is how you open the thing you clicked — in Finder, in a
        // file list, in this app's own Hoard. Renaming on double-click put the
        // rare action on the primary gesture and left the primary action needing
        // a second click somewhere else entirely. Rename is the pencil button
        // and the context menu, where it belongs.
        .simultaneousGesture(TapGesture(count: 2).onEnded { onActivate() })
        .ainkradContextMenu(menuItems)
        .onDrag(onBeginDrag)
        .onDrop(of: [UTType.text], delegate: dropDelegate)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isSelected)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }

    @ViewBuilder
    private var nameLine: some View {
        if isRenaming {
            TextField("Name", text: $renameDraft)
                .textFieldStyle(.plain)
                .font(AinkradFont.display(12, weight: .medium))
                .foregroundStyle(tokens.foreground)
                .focused(renameFocus, equals: .rename(workspace.id))
                .onSubmit(onCommitRename)
                .onKeyPress(.escape) {
                    onCancelRename()
                    return .handled
                }
        } else {
            HStack(spacing: 5) {
                if workspace.isMain {
                    ChevronMark()
                        .fill(tokens.accentSecondary)
                        .frame(width: 9, height: 7)
                        .help("Home workspace")
                }

                // "You are here", as a mark rather than a word. The row used to
                // carry an ACTIVE badge down in the subtitle, and a six-letter
                // capsule in a ~130pt text column simply wins: it is why the
                // name read "Worksp…". A dot says the same thing in 6pt, and the
                // detail header still spells it out where there is room.
                if isActive {
                    Circle()
                        .fill(tokens.accentSecondary)
                        .frame(width: 6, height: 6)
                        .help("Current workspace")
                }

                Text(workspace.name)
                    .font(AinkradFont.display(12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(tokens.foreground.opacity(isSelected || isActive ? 1 : 0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // The name outranks everything else in the column: if
                    // something has to give, it should not be the one piece of
                    // text identifying the row.
                    .layoutPriority(1)
            }
        }
    }

    /// What's in the workspace, and whether it's the one you're in. Both were
    /// 8pt, which is below reading size for anything you actually need.
    private var subtitleLine: some View {
        HStack(spacing: 6) {
            Text(appCount == 0 ? "empty" : "\(appCount) app\(appCount == 1 ? "" : "s")")
                .font(AinkradFont.mono(10))
                .foregroundStyle(tokens.foreground.opacity(0.45))
                // `lineLimit(1)` alone is not enough: under horizontal pressure
                // SwiftUI will still break "2 apps" across two lines rather than
                // truncate. `fixedSize` is what refuses to be compressed at all.
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// The always-visible part: the workspace's ⌘N shortcut. It fades out under
    /// the hover actions, which sit on top of it — while the pointer is on the
    /// row you want the buttons, and the shortcut is for when it isn't.
    private var trailingControls: some View {
        Group {
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(AinkradFont.mono(10))
                    .foregroundStyle(tokens.foreground.opacity(isSelected ? 0.55 : 0.3))
                    .lineLimit(1)
                    .fixedSize()
                    .opacity(hovering ? 0 : 1)
            }
        }
    }

    /// Rename and delete, OVERLAID on the row's trailing edge rather than laid
    /// out in it.
    ///
    /// They used to be in the `HStack`, hidden with `.opacity(0)` and a reserved
    /// slot so hovering wouldn't reflow the row. But an invisible view still
    /// takes part in layout: every row was permanently paying about 48pt for two
    /// buttons that were not there, and the name and subtitle were paying it —
    /// "Workspace 3" truncated to "Worksp…" and "2 apps" broke across two lines.
    /// An overlay costs no width at all, so the text gets it back and hovering
    /// still reflows nothing.
    private var hoverActions: some View {
        HStack(spacing: 2) {
            iconButton("pencil", help: "Rename \(workspace.name)", action: onBeginRename)

            if !workspace.isMain {
                iconButton("xmark", help: "Delete \(workspace.name)", action: onRequestDeletion)
            }
        }
        .padding(.trailing, 6)
        .opacity(hovering ? 1 : 0)
        .allowsHitTesting(hovering)
    }

    private func iconButton(
        _ symbol: String, help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tokens.foreground.opacity(0.6))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var menuItems: [AinkradMenuItem] {
        var items: [AinkradMenuItem] = [
            AinkradMenuItem(title: "Open Workspace", systemName: "arrow.up.forward.square", action: onActivate),
            AinkradMenuItem(title: "Rename", systemName: "pencil", action: onBeginRename),
        ]
        if !workspace.isMain {
            items.append(
                AinkradMenuItem(
                    title: "Delete", systemName: "xmark",
                    isDestructive: true, action: onRequestDeletion))
        }
        return items
    }

    private var rowBackground: some View {
        ChamferShape(cut: AinkradRadius.md)
            .fill(
                isSelected
                    ? tokens.accentPrimary.opacity(0.18)
                    : (hovering
                        ? tokens.foreground.opacity(0.06)
                        : (isActive ? tokens.accentPrimary.opacity(0.07) : .clear))
            )
    }

    private var borderColor: Color {
        if isDropTarget { return tokens.accentSecondary.opacity(0.9) }
        if isSelected { return tokens.accentPrimary.opacity(0.45) }
        return .clear
    }
}
