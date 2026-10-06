import AinkradAppKit
import AinkradHostRuntime
import AppKit
import SwiftUI

/// One open pane, listed in the Workspace Overview's detail pane: its icon, the
/// name the user knows it by, and the actions that act on it. The row itself is
/// the kit's `AinkradListRow`; this view supplies its content and the hover
/// actions laid over its trailing edge.
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
    let isDuplicateMenuOpen: Bool
    let onOpen: () -> Void
    let onToggleDuplicateMenu: () -> Void
    let onClose: () -> Void
    let onBeginDrag: () -> NSItemProvider
    @ViewBuilder let duplicateDestinations: () -> AnyView

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @State private var hovering = false

    /// Colours stay on `DesignTokens`, which carry the user's custom accent;
    /// every scalar comes from the skin.
    private var tokens: DesignTokens { environment.themeManager.tokens }

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

    /// Actions show on hover, and while this row's duplicate popover is open —
    /// or it would vanish out from under the mouse.
    private var showsActions: Bool { hovering || isDuplicateMenuOpen }

    var body: some View {
        AinkradListRow(
            leading: { NeonAppTile(symbol: appIcon, tokens: tokens, size: skin.size.s26) },
            title: title,
            subtitle: subtitle,
            trailing: { shortcutChip.opacity(showsActions ? 0 : 1) }
        )
        // Actions OVERLAID rather than laid out. Hidden-but-present views still
        // take part in layout, so three reserved buttons were charging every
        // row ~76pt that the pane's name needed. An overlay costs no width and
        // still reflows nothing.
        .overlay(alignment: .trailing) {
            HStack(spacing: skin.spacing.xs) {
                AinkradIconButton(
                    systemName: "arrow.up.forward.app", size: skin.size.s24,
                    tooltip: "Open in \(workspace.name)", action: onOpen)

                AinkradIconButton(
                    systemName: "plus.square.on.square", size: skin.size.s24,
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

                AinkradIconButton(
                    systemName: "xmark", size: skin.size.s24, tooltip: "Close \(title)", action: onClose)
            }
            .padding(.trailing, skin.spacing.sm)
            .opacity(showsActions ? 1 : 0)
            .allowsHitTesting(showsActions)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onDrag(onBeginDrag)
        .help("Drag onto a workspace on the left to move it — the app keeps running")
        .animation(reduceMotion ? nil : .easeOut(duration: skin.motion.durations.d0_12), value: hovering)
    }

    /// The ⌥N that reaches this pane in Tabs mode, as a small accent chip.
    @ViewBuilder
    private var shortcutChip: some View {
        if let shortcut = PaneShortcut.label(forOrdinal: ordinal) {
            Text(shortcut)
                .font(AinkradFont.mono(9, weight: .medium))
                .foregroundStyle(tokens.accentSecondary.opacity(skin.opacity.o75))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, skin.size.s3)
                .padding(.vertical, skin.size.s1)
                .background(ChamferShape(cut: skin.cut.c3).fill(tokens.accentSecondary.opacity(skin.opacity.o12)))
                .help("Focus this pane with \(shortcut) in Tabs mode")
        }
    }
}
