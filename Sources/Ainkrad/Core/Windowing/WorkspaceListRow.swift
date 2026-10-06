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
///
/// Not an `AinkradListRow`: that row's title is a plain string, and this one
/// renames in place and carries the home and current-workspace marks beside the
/// name (an Epic 4 gap, "list row with an editable title"). It does wear the
/// kit's row background, so selection and hover read like every other list.
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

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @State private var hovering = false

    /// Colours come from `hostSkin`, which carries the user's custom accent;
    /// every scalar comes from the environment's skin.
    private var tokens: AinkradSkin { environment.themeManager.hostSkin }

    private var appCount: Int { workspace.tileLayout.appIDs.count }

    var body: some View {
        HStack(spacing: skin.size.s10) {
            // The same preview the detail pane features, at row size — so a row
            // shows what is in the workspace, not just how many rectangles it
            // has. Two workspaces holding two side-by-side panes used to be
            // pixel-identical here.
            WorkspaceLayoutPreview(
                workspace: workspace,
                registry: registry,
                style: .thumbnail
            )
            .frame(width: skin.size.s50, height: skin.size.s36)

            VStack(alignment: .leading, spacing: skin.size.s3) {
                nameLine
                subtitleLine
            }

            Spacer(minLength: skin.spacing.xs)

            trailingControls
        }
        // The selection marker is the kit row background's leading accent bar,
        // and its wash: a bar and a badge are different KINDS of mark, so
        // "selected" can't be confused with "current" (the dot by the name).
        .padding(.leading, skin.size.s6)
        .padding(.trailing, skin.size.s9)
        .padding(.vertical, skin.size.s7)
        .overlay(alignment: .trailing) { hoverActions }
        .ainkradRowBackground(isSelected: isSelected, isHovered: hovering)
        .overlay(
            // The kit row background's own chamfer (listRow shape, cut 6), so the
            // drop ring sits on the row's edge.
            ChamferShape(cut: skin.cut.c6)
                .strokeBorder(
                    isDropTarget ? tokens.color(\.accentSecondary).opacity(skin.opacity.o90) : .clear, lineWidth: 1.5)
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
        .animation(reduceMotion ? nil : .easeOut(duration: skin.motion.durations.d0_12), value: isSelected)
        .animation(reduceMotion ? nil : .easeOut(duration: skin.motion.durations.d0_12), value: hovering)
    }

    @ViewBuilder
    private var nameLine: some View {
        if isRenaming {
            // The kit text field owns its focus state, so the overview could not
            // focus it when a rename starts.
            TextField("Name", text: $renameDraft)  // design-lint: allow raw-control kit gap, focus binding
                .textFieldStyle(.plain)
                .font(AinkradFont.display(12, weight: .medium))
                .foregroundStyle(tokens.color(\.foreground))
                .focused(renameFocus, equals: .rename(workspace.id))
                .onSubmit(onCommitRename)
                .onKeyPress(.escape) {
                    onCancelRename()
                    return .handled
                }
        } else {
            HStack(spacing: skin.size.s5) {
                if workspace.isMain {
                    ChevronMark()
                        .fill(tokens.color(\.accentSecondary))
                        .frame(width: skin.size.s9, height: skin.size.s7)
                        .help("Home workspace")
                }

                // "You are here", as a mark rather than a word. The row used to
                // carry an ACTIVE badge down in the subtitle, and a six-letter
                // capsule in a ~130pt text column simply wins: it is why the
                // name read "Worksp…". A dot says the same thing in 6pt, and the
                // detail header still spells it out where there is room.
                if isActive {
                    Circle()
                        .fill(tokens.color(\.accentSecondary))
                        .frame(width: skin.size.s6, height: skin.size.s6)
                        .help("Current workspace")
                }

                Text(workspace.name)
                    .font(AinkradFont.display(12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(tokens.color(\.foreground).opacity(isSelected || isActive ? 1 : skin.opacity.o80))
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
        HStack(spacing: skin.size.s6) {
            Text(appCount == 0 ? "empty" : "\(appCount) app\(appCount == 1 ? "" : "s")")
                .font(AinkradFont.mono(10))
                .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o45))
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
                    .foregroundStyle(tokens.color(\.foreground).opacity(isSelected ? skin.opacity.o55 : skin.opacity.o30))
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
        HStack(spacing: skin.size.s2) {
            iconButton("pencil", help: "Rename \(workspace.name)", action: onBeginRename)

            if !workspace.isMain {
                iconButton("xmark", help: "Delete \(workspace.name)", action: onRequestDeletion)
            }
        }
        .padding(.trailing, skin.size.s6)
        .opacity(hovering ? 1 : 0)
        .allowsHitTesting(hovering)
    }

    private func iconButton(
        _ symbol: String, help: String,
        action: @escaping () -> Void
    ) -> some View {
        AinkradIconButton(systemName: symbol, size: skin.size.s20, tooltip: help, action: action)
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
}
