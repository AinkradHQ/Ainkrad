import AinkradAppKit
import AinkradHostRuntime
import AppKit
import SwiftUI

/// The Workspace Overview's right-hand side: what the selected workspace IS,
/// then what's open in it.
///
/// Split out of `WorkspaceOverviewView` so that file stays a shell — panel,
/// list, footer — and to keep both under the 500-line ceiling. An extension
/// rather than a separate view because every part of it reads the overview's own
/// selection and drag state; threading eight bindings through a new type would
/// have cost more clarity than the split bought.
extension WorkspaceOverviewView {

    @ViewBuilder
    var detailPane: some View {
        if let workspace = selectedWorkspace {
            VStack(alignment: .leading, spacing: 0) {
                detailHeader(workspace)

                if workspace.tileLayout.blocks.isEmpty {
                    // ONE empty state, not two.
                    //
                    // An empty workspace used to get a full-size preview saying
                    // "empty" AND a separate "No apps in this workspace" block
                    // beneath it — the same fact, twice, in ~570pt. Worse, that
                    // made the emptiest possible workspace the TALLEST thing the
                    // panel ever had to show, which is what stopped it hugging.
                    // A workspace with nothing in it has nothing to preview, so
                    // the message is the preview.
                    emptyWorkspaceState(workspace)
                } else {
                    // The recognition anchor, and the screen's largest target for
                    // its primary action. Clicking it switches, because the
                    // biggest thing on screen should do the thing you came to do.
                    // A button whose label is the preview itself; no kit button
                    // takes a custom label.
                    Button {  // design-lint: allow raw-control kit gap, content label
                        activate(workspace)
                    } label: {
                        WorkspaceLayoutPreview(
                            workspace: workspace,
                            registry: environment.registry,
                            style: .feature
                        )
                        // Screen-shaped, and given exactly the height the app
                        // grid leaves over — see `previewHeight(forAppCount:)`.
                        // The aspect ratio then sets its width, so it stays a
                        // miniature of a screen rather than a stretched panel.
                        .aspectRatio(Self.previewAspectRatio, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(
                            height: Self.previewHeight(
                                forAppCount: workspace.tileLayout.blocks.count)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(
                        workspace.id == manager.activeWorkspaceID
                            ? "You're in \(workspace.name)"
                            : "Switch to \(workspace.name)"
                    )
                    .padding(.horizontal, skin.size.s18)
                    .padding(.bottom, skin.size.s14)

                    appListHeader(workspace)

                    appList(workspace)
                }
            }
        } else {
            VStack(spacing: skin.size.s10) {
                Image(systemName: "rectangle.split.3x1")
                    .font(skin.font(AinkradFontToken(sizeKey: "t30", weight: "light", scaled: false)))
                    .foregroundStyle(tokens.accentPrimary.opacity(skin.opacity.o50))
                Text("Select a workspace").font(AinkradFont.display(13)).foregroundStyle(
                    tokens.foreground.opacity(skin.opacity.o55))
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.noSelectionHeight)
        }
    }

    /// The empty-workspace state: the dashed frame that stands in for a preview,
    /// carrying the reason it's empty and what to do about it.
    private func emptyWorkspaceState(_ workspace: Workspace) -> some View {
        VStack(spacing: skin.spacing.sm) {
            Image(systemName: "square.dashed")
                .font(skin.font(AinkradFontToken(sizeKey: "t24", weight: "light", scaled: false)))
                .foregroundStyle(tokens.foreground.opacity(skin.opacity.o30))
            Text("No apps in this workspace")
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground.opacity(skin.opacity.o45))
            Text("Drag an app here from another workspace, or open one from the Launcher.")
                .font(AinkradFont.display(11))
                .foregroundStyle(tokens.foreground.opacity(skin.opacity.o30))
                .multilineTextAlignment(.center)
                // A measure, not the full column width — a line of guidance
                // stretched across ~1100pt is harder to read than one that wraps.
                .frame(maxWidth: skin.size.s320)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.emptyWorkspaceHeight)
        .background(
            ChamferShape(cut: skin.radius.sm)
                .strokeBorder(
                    tokens.foreground.opacity(skin.opacity.o16),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
        )
        .padding(.horizontal, skin.size.s18)
        .padding(.bottom, skin.spacing.lg)
    }

    /// Roughly the proportions of the workspace canvas the preview stands for.
    static var previewAspectRatio: CGFloat { 16.0 / 10.0 }
    /// The preview's ceiling — past this it stops being a preview.
    static let maximumPreviewHeight: CGFloat = 340
    /// Its floor — below this the pane cells stop being readable.
    static let minimumPreviewHeight: CGFloat = 150

    /// The detail column's height, and it is a CONSTANT.
    ///
    /// Deriving it from the selected workspace made the panel the right size for
    /// every individual state and the wrong size for moving between them: it
    /// jumped as the selection moved down the list — 382pt on an empty workspace,
    /// 624pt on a filled one — and a switcher that resizes under the pointer is
    /// worse than one carrying some slack. Height stability beats per-state
    /// tightness on a screen whose whole purpose is moving between states.
    ///
    /// Sized for the most common filled case (a full-height preview above one
    /// row of apps); every other case is fitted into it rather than changing it.
    static var detailHeight: CGFloat {
        detailHeaderHeight
            + previewBottomPadding
            + maximumPreviewHeight
            + appSectionHeaderHeight
            + appGridHeight(count: 3)
    }

    /// Name, badges and the Open Workspace button.
    static let detailHeaderHeight: CGFloat = 60
    /// The "OPEN APPS n" label and its spacing.
    static let appSectionHeaderHeight: CGFloat = 30
    static let previewBottomPadding: CGFloat = 14
    /// The nothing-selected placeholder — the same height as everything else, so
    /// the panel does not resize when the selection is cleared either.
    static var noSelectionHeight: CGFloat { detailHeight }

    /// The preview takes whatever the app grid doesn't, so the column's total
    /// stays `detailHeight` whatever the pane count.
    ///
    /// This is what makes a constant height cost nothing: the slack has somewhere
    /// useful to go. Few panes means a larger preview, many panes a smaller one,
    /// and the panel never moves.
    static func previewHeight(forAppCount count: Int) -> CGFloat {
        let fixed =
            detailHeaderHeight + previewBottomPadding
            + appSectionHeaderHeight + appGridHeight(count: count)
        return min(max(detailHeight - fixed, minimumPreviewHeight), maximumPreviewHeight)
    }

    /// The merged empty-workspace state fills the same column, so an empty
    /// workspace and a busy one produce identical panels.
    static var emptyWorkspaceHeight: CGFloat { detailHeight - detailHeaderHeight - 16 }

    private func detailHeader(_ workspace: Workspace) -> some View {
        HStack(spacing: skin.size.s10) {
            Text(workspace.name)
                .font(AinkradFont.display(16, weight: .semibold))
                .foregroundStyle(tokens.foreground)
                .lineLimit(1)

            if workspace.id == manager.activeWorkspaceID {
                Text("ACTIVE").font(AinkradFont.mono(9, weight: .bold)).tracking(1)
                    .foregroundStyle(tokens.accentSecondary)
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, skin.size.s6).padding(.vertical, skin.size.s2)
                    .background(Capsule().fill(tokens.accentSecondary.opacity(skin.opacity.o15)))
            }

            // Which mode you'll land in. The overview showed no trace of this,
            // so a workspace that would open as tabs was indistinguishable from
            // one that opens tiled until you were already in it.
            if workspace.tileLayout.blocks.count > 1 {
                Text(workspace.viewMode == .focus ? "TABS" : "SPLIT")
                    .font(AinkradFont.mono(9, weight: .medium)).tracking(1)
                    .foregroundStyle(tokens.foreground.opacity(skin.opacity.o50))
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, skin.size.s5).padding(.vertical, skin.size.s2)
                    .background(Capsule().fill(tokens.foreground.opacity(skin.opacity.o08)))
            }

            Spacer()

            if workspace.id != manager.activeWorkspaceID {
                AinkradButton(title: "Open Workspace", style: .primary, icon: "arrow.up.forward.square") {
                    activate(workspace)
                }
            }
        }
        .padding(.horizontal, skin.size.s18).padding(.top, skin.spacing.lg).padding(.bottom, skin.spacing.md)
    }

    /// Static, so it reads the standard skin (as `OverlayChrome` does).
    static let appGridColumns = Array(
        repeating: GridItem(.flexible(), spacing: AinkradSkin.standard.size.s6), count: 3)

    /// Exactly the height the grid's rows need, capped so a workspace with many
    /// panes scrolls instead of pushing the preview off the panel.
    static func appGridHeight(count: Int) -> CGFloat {
        let columns = CGFloat(appGridColumns.count)
        let rows = (CGFloat(count) / columns).rounded(.up)
        return min(rows * 58 + 16, 262)
    }

    /// A section label, so the app rows read as a subordinate list rather than
    /// as the point of the screen.
    @ViewBuilder
    private func appListHeader(_ workspace: Workspace) -> some View {
        let count = workspace.tileLayout.blocks.count
        if count > 0 {
            HStack(spacing: skin.size.s6) {
                Text("OPEN APPS")
                    .font(AinkradFont.mono(9, weight: .semibold)).kerning(1.5)
                    .foregroundStyle(tokens.foreground.opacity(skin.opacity.o45))
                    .lineLimit(1).fixedSize()
                Text("\(count)")
                    .font(AinkradFont.mono(9))
                    .foregroundStyle(tokens.accentSecondary.opacity(skin.opacity.o80))
                Spacer()
            }
            .padding(.horizontal, skin.size.s18)
            .padding(.bottom, skin.size.s7)
        }
    }

    /// Switching is one call in one place, because it is reachable from the
    /// preview, the header button, a row's double-click, its context menu and ↩.
    func activate(_ workspace: Workspace) {
        manager.switchTo(workspace.id)
        onDismiss()
    }

    /// The open apps. Only called for a workspace that has some — an empty one
    /// shows `emptyWorkspaceState` in place of the preview and this list.
    private func appList(_ workspace: Workspace) -> some View {
        let blocks = workspace.tileLayout.blocks
        // Three across, not one per line. Each row carries an icon and two
        // short strings; given to a column ~1100pt wide, one per line spent
        // the whole width on nothing and the whole height on three rows.
        //
        // A FIXED three columns rather than `.adaptive`: the row count is
        // then knowable, which is what lets the height below be exact
        // instead of an estimate that leaves slack inside a scroll view.
        return ScrollView {
            LazyVGrid(columns: Self.appGridColumns, spacing: skin.size.s6) {
                ForEach(Array(blocks.enumerated()), id: \.element.id) { ordinal, block in
                    appRow(block, ordinal: ordinal, workspace: workspace)
                }
            }
            .padding(.horizontal, skin.spacing.lg).padding(.bottom, skin.spacing.lg)
        }
        .frame(maxHeight: Self.appGridHeight(count: blocks.count))
    }

    private func appRow(
        _ block: Block, ordinal: Int, workspace: Workspace
    ) -> some View {
        let app = environment.registry.allApps.first { $0.id == block.appID }
        let sourceLabel: String = {
            switch app?.source {
            case .plugin: return "Plugin"
            case .builtIn: return "Built-in"
            case .none: return ""
            }
        }()

        return WorkspaceAppRow(
            block: block,
            workspace: workspace,
            ordinal: ordinal,
            appName: app?.displayName,
            appIcon: app?.icon ?? "app",
            sourceLabel: sourceLabel,
            isDuplicateMenuOpen: duplicateMenuBlockID == block.id,
            onOpen: {
                manager.switchTo(workspace.id)
                workspace.tileLayout.focus(block.id)
                onDismiss()
            },
            onToggleDuplicateMenu: {
                duplicateMenuBlockID = duplicateMenuBlockID == block.id ? nil : block.id
            },
            onClose: { workspace.tileLayout.close(block.id) },
            onBeginDrag: {
                draggedApp = DraggedApp(blockID: block.id, sourceWorkspaceID: workspace.id)
                return NSItemProvider(object: "appmove:\(block.id.uuidString)" as NSString)
            },
            duplicateDestinations: { AnyView(duplicateDestinations(block)) }
        )
    }

    /// The "duplicate to…" destinations, drawn in the HUD rather than by an
    /// AppKit menu.
    private func duplicateDestinations(_ block: Block) -> some View {
        VStack(alignment: .leading, spacing: skin.size.s2) {
            ForEach(manager.workspaces) { destination in
                destinationRow("Duplicate to \(destination.name)") {
                    manager.duplicateApp(block.appID, to: destination.id)
                    duplicateMenuBlockID = nil
                }
            }
            destinationRow("Duplicate to New Workspace") {
                let destination = manager.createWorkspace()
                manager.duplicateApp(block.appID, to: destination.id)
                duplicateMenuBlockID = nil
            }
        }
        .frame(minWidth: skin.size.s200, alignment: .leading)
    }

    private func destinationRow(_ title: String, action: @escaping () -> Void) -> some View {
        AinkradListRow(onTap: action, leading: { EmptyView() }, title: title, trailing: { EmptyView() })
    }
}
