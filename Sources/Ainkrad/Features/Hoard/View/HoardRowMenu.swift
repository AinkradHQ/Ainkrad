import AinkradAppKit
import AinkradAppKitUI
import AinkradHostRuntime
import AppKit
import SwiftUI

/// What a row's context menu can do.
///
/// A struct of closures rather than passing `HoardActions` down into the list:
/// the list stays testable and ignorant of the engine, which is the same reason
/// `gitStatus` and `isCut` arrive as closures.
struct FileRowMenuActions {
    var open: (FileEntry) -> Void
    var rename: (FileEntry) -> Void
    var copy: () -> Void
    var cut: () -> Void
    var paste: () -> Void
    var compress: () -> Void
    var extractArchives: () -> Void
    var trash: () -> Void
    var togglePin: (FileEntry) -> Void
    var canExtract: (FileEntry) -> Bool
    var isPinned: (FileEntry) -> Bool
}

/// One row of the menu: what it says, the chord that does the same thing, and
/// whether it is the dangerous one.
struct HoardMenuAction: Identifiable {
    let id = UUID()
    var title: String
    var symbol: String
    /// Shown as an `AinkradKbd` chip. `nil` where no chord does exactly this.
    var shortcut: String?
    var isDestructive = false
    var run: () -> Void
}

/// Zero-footprint right-click detector.
///
/// The reason this exists rather than the kit's `.ainkradContextMenu`: that
/// installs its catcher in the row's BACKGROUND, and these rows put opaque
/// interactive content on top (`contentShape` plus tap and double-tap
/// gestures), so the catcher never received the event and right-click stopped
/// working entirely.
///
/// This one sits in an OVERLAY — above the content, where the event actually
/// arrives — and stays invisible to everything else by returning `nil` from
/// `hitTest` for any event that is not a right-click. Without that override an
/// overlaid `NSView` would swallow every left click and break selection.
private struct HoardRightClickCatcher: NSViewRepresentable {
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onRightClick = onRightClick
    }

    final class CatcherView: NSView {
        var onRightClick: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            switch event.type {
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
                return super.hitTest(point)
            // ctrl-click is a right-click on macOS, and someone on a trackpad
            // may well use it.
            case .leftMouseDown where event.modifierFlags.contains(.control):
                return super.hitTest(point)
            default:
                return nil
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            onRightClick?()
        }

        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) { onRightClick?() } else { super.mouseDown(with: event) }
        }
    }
}

/// The menu itself, in the Cardinal HUD language.
struct HoardContextMenuList: View {
    let actions: [HoardMenuAction]
    /// Passed IN, never read from the environment.
    ///
    /// `ainkradFloatingPanel` hosts its content in a separate `NSHostingView`,
    /// so the pane's `AppEnvironment` does not reach it — reading it here
    /// crashed the app the moment the panel measured its content. The kit
    /// re-injects theme, typography and status colours; anything else has to
    /// be captured at the call site.
    let tokens: DesignTokens
    let onSelect: () -> Void

    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradStatusColors) private var statusColors
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s1) {
            ForEach(actions) { action in
                row(action)
            }
        }
        .padding(AinkradSpacing.xs)
        .frame(width: skin.size.s232)
        // `.behindWindow`: this panel is its own window, so a `.withinWindow`
        // blur has nothing to sample and the menu reads as a flat opaque slab
        // instead of matching the app's other overlays.
        .hudPanelChrome(tokens: tokens, blending: .behindWindow)
    }

    private func row(_ action: HoardMenuAction) -> some View {
        HoardContextMenuRow(action: action, tokens: tokens, onSelect: onSelect)
    }
}

private struct HoardContextMenuRow: View {
    let action: HoardMenuAction
    let tokens: DesignTokens
    let onSelect: () -> Void

    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradStatusColors) private var statusColors
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @Environment(\.ainkradSkin) private var skin
    @State private var hovering = false

    private var tint: Color {
        action.isDestructive ? statusColors.danger : tokens.foreground.opacity(skin.opacity.o90)
    }

    var body: some View {
        Button {  // design-lint: allow raw-control kit gap, context menu open hook
            action.run()
            onSelect()
        } label: {
            HStack(spacing: AinkradSpacing.sm) {
                Image(systemName: action.symbol)
                    .font(skin.font(AinkradFontToken(sizeKey: "t11", weight: "semibold", scaled: false)))
                    .frame(width: skin.size.s15)
                Text(action.title)
                    .font(AinkradFontResolver.font(.body, typography: typo))
                Spacer(minLength: AinkradSpacing.md)
                // The chord as a real key chip, right-aligned into its own
                // column — the menu teaches the keyboard rather than replacing
                // it.
                if let shortcut = action.shortcut {
                    AinkradKbd(shortcut)
                }
            }
            .foregroundStyle(tint)
            .padding(.horizontal, AinkradSpacing.sm)
            .padding(.vertical, AinkradSpacing.xs)
            .background(
                ChamferShape(cut: skin.cut.c4).fill(
                    hovering ? tokens.accentSecondary.opacity(skin.opacity.o14) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The panel gives its first button keyboard focus, and SwiftUI's
        // default focus ring is a heavy system rectangle that has nothing to do
        // with this design language. Hover is the only highlight here.
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: skin.motion.durations.d0_08), value: hovering)
    }
}

extension View {
    /// The right-click menu for one row.
    ///
    /// Until this existed, **every** operation in Hoard was keyboard-only —
    /// rename was F2 and nothing else, which on a Mac laptop means Fn+F2, so
    /// the single most ordinary thing you do to a file was effectively hidden.
    func fileRowMenu(
        entry: FileEntry, tab: HoardTab,
        actions: FileRowMenuActions
    ) -> some View {
        modifier(HoardRowMenu(entry: entry, tab: tab, actions: actions))
    }
}

private struct HoardRowMenu: ViewModifier {
    let entry: FileEntry
    let tab: HoardTab
    let actions: FileRowMenuActions

    /// Read HERE, where the pane's environment exists, and handed to the panel
    /// as a plain value.
    @Environment(AppEnvironment.self) private var environment
    @State private var isPresented = false

    /// Right-clicking a row that is NOT part of the current selection retargets
    /// onto it — the standard behaviour everywhere, and the alternative is a
    /// menu that appears over one file and acts on three others.
    private func targeting(_ action: @escaping () -> Void) -> () -> Void {
        {
            tab.targetContextMenu(at: entry)
            action()
        }
    }

    private var menuActions: [HoardMenuAction] {
        var items: [HoardMenuAction] = [
            HoardMenuAction(
                title: "Open",
                symbol: entry.isDirectory ? "folder" : "arrow.up.forward.app",
                shortcut: "\u{21A9}",
                run: targeting { actions.open(entry) }),
            HoardMenuAction(
                title: "Rename", symbol: "character.cursor.ibeam",
                shortcut: "\u{2318}R",
                run: targeting { actions.rename(entry) }),
            HoardMenuAction(
                title: "Copy", symbol: "doc.on.doc", shortcut: "\u{2318}C",
                run: targeting(actions.copy)),
            HoardMenuAction(
                title: "Cut", symbol: "scissors", shortcut: "\u{2318}X",
                run: targeting(actions.cut)),
            HoardMenuAction(
                title: "Paste", symbol: "doc.on.clipboard", shortcut: "\u{2318}V",
                run: actions.paste),
            HoardMenuAction(
                title: "Compress", symbol: "archivebox", shortcut: "\u{2325}A",
                run: targeting(actions.compress)),
        ]

        if actions.canExtract(entry) {
            items.append(
                HoardMenuAction(
                    title: "Extract", symbol: "arrow.up.bin",
                    shortcut: "\u{2325}E",
                    run: targeting(actions.extractArchives)))
        }

        if entry.isDirectory {
            // NO shortcut: ⌘D pins the folder you are INSIDE, a different
            // target from the folder you right-clicked. Showing ⌘D here would
            // teach a chord that does something else.
            let pinned = actions.isPinned(entry)
            items.append(
                HoardMenuAction(
                    title: pinned ? "Remove from Favourites" : "Add to Favourites",
                    symbol: pinned ? "star.slash" : "star",
                    shortcut: nil,
                    run: { actions.togglePin(entry) }))
        }

        // Last and danger-tinted. It routes to the Trash like every delete
        // here; nothing in this app deletes permanently.
        items.append(
            HoardMenuAction(
                title: "Move to Trash", symbol: "trash",
                shortcut: "\u{2318}\u{232B}", isDestructive: true,
                run: targeting(actions.trash)))
        return items
    }

    func body(content: Content) -> some View {
        content
            .overlay(
                HoardRightClickCatcher {
                    // Retarget BEFORE the menu opens, so the highlighted row
                    // is the one the menu is about.
                    tab.targetContextMenu(at: entry)
                    isPresented = true
                }
            )
            // A floating panel, never `.contextMenu`: that renders a system
            // `NSMenu` — native chrome, native highlight — inside an interface
            // that is deliberately not macOS-shaped. The panel is app-level, so
            // it is also never clipped by the scroll view's bounds.
            .ainkradFloatingPanel(isPresented: $isPresented, maxHeight: 360) {
                // `.environment(environment)` is REQUIRED, not defensive: the
                // panel is a separate `NSHostingView`, and `hudPanelChrome`
                // reads `AppEnvironment` for the live opacity/blur settings.
                // Without this the app crashes the instant the panel measures
                // its content.
                HoardContextMenuList(
                    actions: menuActions,
                    tokens: environment.themeManager.tokens
                ) {
                    isPresented = false
                }
                .environment(environment)
            }
    }
}

extension View {
    /// The sidebar's one-item menu, in the same language as the file rows'.
    func sidebarRootMenu(
        root: SidebarRoot,
        onRemove: @escaping (SidebarRoot) -> Void
    ) -> some View {
        modifier(SidebarRootMenu(root: root, onRemove: onRemove))
    }
}

private struct SidebarRootMenu: ViewModifier {
    let root: SidebarRoot
    let onRemove: (SidebarRoot) -> Void

    @Environment(AppEnvironment.self) private var environment
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .overlay(HoardRightClickCatcher { isPresented = true })
            .ainkradFloatingPanel(isPresented: $isPresented, maxHeight: 120) {
                HoardContextMenuList(
                    actions: [
                        HoardMenuAction(
                            title: "Remove from Favourites",
                            symbol: "star.slash",
                            shortcut: nil,
                            run: { onRemove(root) })
                    ],
                    tokens: environment.themeManager.tokens
                ) { isPresented = false }
                .environment(environment)
            }
    }
}
