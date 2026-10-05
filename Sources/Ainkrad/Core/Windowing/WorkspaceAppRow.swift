import AinkradAppKit
import AinkradHostRuntime
import AppKit
import SwiftUI

/// One open pane, listed in the Workspace Overview's detail pane: its icon, the
/// name the user knows it by, and the actions that act on it.
struct WorkspaceAppRow: View {
    let block: Block
    let workspace: Workspace
    /// Zero-based position in the workspace, so the row can name the ⌥N that
    /// reaches this pane. Three unnamed terminals produced three identical rows
    /// — "Rune / Plugin", three times — which tells you nothing about which is
    /// which. The shortcut is a real, actionable distinguisher, and it ties this
    /// list to the tab strip you'd use to get there.
    let ordinal: Int
    let appName: String?
    let appIcon: String
    let sourceLabel: String
    let tokens: DesignTokens
    let isDuplicateMenuOpen: Bool
    let onOpen: () -> Void
    let onToggleDuplicateMenu: () -> Void
    let onClose: () -> Void
    let onBeginDrag: () -> NSItemProvider
    @ViewBuilder let duplicateDestinations: () -> AnyView

    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @State private var hovering = false

    /// The name the user gave this pane, falling back to the app's own.
    ///
    /// The row used to show the app's display name and, beneath it, "Plugin" or
    /// "Built-in". But panes are renameable now (their Focus-Mode tabs can be
    /// renamed), so a pane called "build" showed up here as plain "Rune" —
    /// the overview couldn't tell you which of your four terminals you were
    /// looking at, which is precisely what it is for. The custom name leads, and
    /// the app it is an instance of becomes the subtitle. Where there is no
    /// custom name, the subtitle stays the provenance it was.
    private var title: String { block.displayTitle(appName: appName) }

    private var hasCustomTitle: Bool {
        guard let custom = block.title else { return false }
        return !custom.isEmpty && custom != appName
    }

    private var subtitle: String {
        hasCustomTitle ? (appName ?? block.appID) : sourceLabel
    }

    var body: some View {
        HStack(spacing: 11) {
            NeonAppTile(symbol: appIcon, tokens: tokens, size: 26)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(AinkradFont.display(12, weight: .medium))
                        .foregroundStyle(tokens.foreground.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let shortcut = PaneShortcut.label(forOrdinal: ordinal) {
                        Text(shortcut)
                            .font(AinkradFont.mono(9, weight: .medium))
                            .foregroundStyle(tokens.accentSecondary.opacity(0.75))
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(ChamferShape(cut: 3).fill(tokens.accentSecondary.opacity(0.12)))
                            .help("Focus this pane with \(shortcut) in Tabs mode")
                    }
                }

                Text(subtitle)
                    .font(AinkradFont.mono(10))
                    .foregroundStyle(tokens.foreground.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        // Actions appear on hover (and while this row's duplicate popover is
        // open, or it would vanish out from under the mouse), OVERLAID rather
        // than laid out. Hidden-but-present views still take part in layout, so
        // three reserved buttons were charging every row ~76pt that the pane's
        // name needed. An overlay costs no width and still reflows nothing.
        .overlay(alignment: .trailing) {
            HStack(spacing: 4) {
                rowButton("arrow.up.forward.app", help: "Open in \(workspace.name)", action: onOpen)

                AinkradIconButton(
                    systemName: "plus.square.on.square", size: 24,
                    tooltip: "Duplicate \(title) to another workspace",
                    action: onToggleDuplicateMenu
                )
                .ainkradPopover(
                    isPresented: Binding(
                        get: { isDuplicateMenuOpen },
                        set: { if !$0 { onToggleDuplicateMenu() } })
                ) {
                    duplicateDestinations()
                }

                rowButton("xmark", help: "Close \(title)", action: onClose)
            }
            .padding(.trailing, 8)
            .opacity(hovering || isDuplicateMenuOpen ? 1 : 0)
            .allowsHitTesting(hovering || isDuplicateMenuOpen)
        }
        .background(
            ChamferShape(cut: AinkradRadius.sm)
                .fill(tokens.surfaceElevated.opacity(hovering ? 0.6 : 0.4))
        )
        .overlay(
            ChamferShape(cut: AinkradRadius.sm)
                .strokeBorder(tokens.foreground.opacity(hovering ? 0.14 : 0.06), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onDrag(onBeginDrag)
        .help("Drag onto a workspace on the left to move it — the app keeps running")
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }

    private func rowButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tokens.foreground.opacity(0.6))
                .frame(width: 24, height: 24)
                .background(Circle().fill(tokens.surfaceElevated.opacity(0.5)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
