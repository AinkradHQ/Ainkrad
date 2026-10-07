import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// Focus Mode's pane switcher: a horizontal tab strip along the TOP edge of
/// the canvas — one tab per open panel, the active one filling the canvas
/// below it.
///
/// It replaces the vertical chip rail that used to sit on the right. Tabs read
/// as tabs (icon + name, the active one lit and connected to the surface
/// beneath), sit where the pane's own title bar used to be, and each carries
/// the pane's name — double-click, or right-click → Rename, to edit it. A tab's
/// × closes its pane, which is now the pointer-driven way to close a panel that
/// the removed pane header's × used to be.
///
/// Selecting a tab moves the host's focus AND hands the keyboard to the app in
/// the pane that comes forward (see `PaneKeyFocusAnchor`) — the tab you clicked
/// is the one you can type into.
///
/// Not `AinkradTabs`: the kit's tabs are text labels only, and a pane tab also
/// carries its app tile, its ⌥N chip, a rename field and a close button — an
/// Epic 4 gap ("pane tab strip"). Local, on skin tokens and kit buttons.
struct FocusTabStrip: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradSkin) private var skin
    let workspace: Workspace

    /// The pane whose tab is being renamed, if any. Held here rather than in
    /// the tab so only one edit can ever be live at a time.
    @State private var renamingBlockID: UUID?
    private var tileLayout: TileLayout { workspace.tileLayout }

    var body: some View {
        HStack(spacing: skin.spacing.xs) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: skin.size.s2) {
                    ForEach(Array(tileLayout.blocks.enumerated()), id: \.element.id) { index, block in
                        FocusTab(
                            block: block,
                            ordinal: index,
                            appName: appName(for: block),
                            symbol: symbol(for: block),
                            isActive: tileLayout.focusedBlockID == block.id,
                            isRenaming: renamingBlockID == block.id,
                            canClose: tileLayout.blocks.count > 1,
                            onSelect: { select(block) },
                            onBeginRename: { renamingBlockID = block.id },
                            onEndRename: { renamingBlockID = nil },
                            onRename: { tileLayout.rename(block.id, to: $0) },
                            onClose: {
                                environment.sounds.play(.appClose)
                                tileLayout.close(block.id)
                            }
                        )
                    }
                }
                .padding(.horizontal, skin.size.s2)
            }

            AinkradIconButton(
                systemName: "rectangle.split.2x2", size: skin.size.s24, tooltip: "Back to Split Mode (⌘M)"
            ) {
                workspace.viewMode = .split
                environment.workspaceManager.persist()
                environment.sounds.play(.focusMode)
            }
        }
        // A tab being renamed must not be yanked out from under the editor by a
        // pane closing elsewhere; clear the edit if its pane is gone.
        .onChange(of: tileLayout.blocks.count) { _, _ in
            if let renamingBlockID, !tileLayout.blocks.contains(where: { $0.id == renamingBlockID }) {
                self.renamingBlockID = nil
            }
        }
    }

    private func select(_ block: Block) {
        guard tileLayout.focusedBlockID != block.id else { return }
        // Committing any live rename first: clicking away from an edit should
        // leave the edit, not carry it onto the newly selected tab.
        renamingBlockID = nil
        // NOT wrapped in `withAnimation`. Focusing a pane is observed by every
        // BlockView (border, glow, brackets, dimming) and by the canvas that
        // swaps which pane is visible; driving all of that from one explicit
        // transaction animated the pane swap itself, which is what stuttered.
        // Each affected view already declares its own `.animation(value:)` for
        // the properties that should ease — let them.
        tileLayout.focus(block.id)
    }

    private func appName(for block: Block) -> String? {
        environment.registry.allApps.first { $0.id == block.appID }?.displayName
    }

    private func symbol(for block: Block) -> String {
        environment.registry.allApps.first { $0.id == block.appID }?.icon ?? "app"
    }
}

/// One tab: the app's neon tile, the pane's name (editable in place) and a ×
/// that only takes space on the active or hovered tab, so a row of inactive
/// tabs stays legible instead of being half occupied by glyphs.
private struct FocusTab: View {
    let block: Block
    /// Zero-based position in the strip, so the tab can show its own ⌥N.
    let ordinal: Int
    let appName: String?
    let symbol: String
    let isActive: Bool
    let isRenaming: Bool
    let canClose: Bool
    let onSelect: () -> Void
    let onBeginRename: () -> Void
    let onEndRename: () -> Void
    let onRename: (String) -> Void
    let onClose: () -> Void

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    /// Colours come from `hostSkin`, which carries the user's custom accent;
    /// every scalar comes from the environment's skin.
    private var tokens: AinkradSkin { environment.themeManager.hostSkin }
    private var title: String { block.displayTitle(appName: appName) }
    /// The pencil and × only show on the active or hovered tab.
    private var showsTabActions: Bool { isActive || hovering }

    var body: some View {
        HStack(spacing: skin.size.s6) {
            // The tab wears its own shortcut. Only the first nine get one —
            // ⌥1-9 is all the chord has room for, and a tenth tab showing
            // nothing is honest about that.
            if let shortcut = PaneShortcut.label(forOrdinal: ordinal) {
                Text(shortcut)
                    // A two-character label, but a squeezed tab is still a text
                    // container looking for a break — the workspace list's
                    // ACTIVE badge wrapped to "ACT"/"IVE" for exactly this.
                    .font(AinkradFont.mono(9, weight: .medium))
                    .foregroundStyle(tokens.color(\.accentSecondary).opacity(isActive ? skin.opacity.o95 : skin.opacity.o50))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, skin.size.s3)
                    .padding(.vertical, skin.size.s1)
                    .background(
                        ChamferShape(cut: skin.cut.c3)
                            .fill(tokens.color(\.accentSecondary).opacity(isActive ? skin.opacity.o16 : skin.opacity.o08))
                    )
            }

            NeonAppTile(symbol: symbol, tokens: tokens, size: skin.size.s16)
                .opacity(isActive ? 1 : skin.opacity.o60)

            if isRenaming {
                // The kit text field owns its focus state; this one must take
                // focus the moment the rename starts.
                TextField("", text: $draft)  // design-lint: allow raw-control kit gap, focus binding
                    .textFieldStyle(.plain)
                    .font(AinkradFont.display(11, weight: .medium))
                    .foregroundStyle(tokens.color(\.foreground))
                    .frame(maxWidth: .infinity)
                    .focused($fieldFocused)
                    .onSubmit(commit)
                    // Losing focus commits too: clicking elsewhere should keep
                    // what was typed, not silently discard it.
                    .onChange(of: fieldFocused) { _, focused in
                        if !focused { commit() }
                    }
                    .onAppear {
                        draft = title
                        fieldFocused = true
                    }
            } else {
                Text(title)
                    .font(AinkradFont.display(11, weight: isActive ? .medium : .regular))
                    .kerning(0.4)
                    .foregroundStyle(tokens.color(\.foreground).opacity(isActive ? skin.opacity.o95 : skin.opacity.o55))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Rename: an explicit button rather than a double-click, so that
            // selecting a tab has no gesture to disambiguate against (see the
            // tap gesture below).
            if !isRenaming {
                AinkradIconButton(systemName: "pencil", size: skin.size.s14, tooltip: "Rename", action: onBeginRename)
                    .opacity(showsTabActions ? 1 : 0)
                    .allowsHitTesting(showsTabActions)
            }

            // The slot is always reserved and the button fades in and out
            // inside it. Inserting/removing the button instead re-laid the
            // title on every hover — a visible text reflow just from moving
            // the mouse across the strip.
            if canClose {
                AinkradIconButton(systemName: "xmark", size: skin.size.s14, tooltip: "Close (⌘W)", action: onClose)
                    .opacity(showsTabActions && !isRenaming ? 1 : 0)
                    .allowsHitTesting(showsTabActions && !isRenaming)
            }
        }
        .padding(.horizontal, skin.size.s10)
        // Tabs read as tabs at this width — a name has room to be a real name
        // rather than an ellipsis, and the row stays a stable set of targets
        // instead of resizing tab-by-tab as titles change. `maxWidth` caps a
        // long rename; `minWidth` is what stops a short one from shrinking to
        // a chip.
        .frame(minWidth: skin.size.s165, maxWidth: skin.size.s250, alignment: .leading)
        .frame(height: skin.size.s30)
        .background {
            // The active fill is drawn on every tab and cross-fades by
            // opacity, rather than one shared fill migrating between tabs via
            // `matchedGeometryEffect`. A matched-geometry fill inside a
            // horizontal `ScrollView` is measured against the scroll content's
            // moving coordinate space, so it flew in from the wrong place — or
            // from off-screen — on switches; that was the jump on every click.
            // Two cross-fading fills cannot fly anywhere.
            ChamferShape(cut: skin.radius.sm)
                .fill(tokens.color(\.accentPrimary).opacity(skin.opacity.o18))
                .opacity(isActive ? 1 : 0)
                .overlay {
                    ChamferShape(cut: skin.radius.sm)
                        .fill(tokens.color(\.foreground).opacity(skin.opacity.o06))
                        .opacity(!isActive && hovering ? 1 : 0)
                }
        }
        .overlay {
            ChamferShape(cut: skin.radius.sm)
                .strokeBorder(tokens.color(\.accentPrimary).opacity(skin.opacity.o45), lineWidth: 1)
                .opacity(isActive ? 1 : 0)
        }
        // An accent bar along the active tab's top edge, drawn on every tab and
        // cross-faded like the fill (no `matchedGeometryEffect` — that is what
        // made the highlight fly across the strip inside a ScrollView). It gives
        // the selection an edge to read rather than only a wash of colour, and
        // it grows in from the tab's centre, which points at the pane below.
        .overlay(alignment: .top) {
            Capsule()
                .fill(tokens.color(\.accentSecondary))
                .frame(height: skin.size.s2)
                .scaleEffect(x: isActive ? 1 : 0.3, anchor: .center)
                .opacity(isActive ? 1 : 0)
                .padding(.horizontal, skin.size.s6)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // Single tap fires IMMEDIATELY; the double-tap runs alongside it as a
        // SIMULTANEOUS gesture.
        //
        // Declaring `.onTapGesture(count: 2)` next to a single-tap handler —
        // which is what this did originally — makes SwiftUI wait out the
        // double-click interval before delivering the single tap. That is what
        // made switching tabs take about a second: the switch was never slow, it
        // was waiting to find out whether a second click was coming.
        //
        // A simultaneous gesture doesn't arbitrate, so both work: instant
        // selection AND double-click to rename. `FileRowView` already uses this
        // exact pattern, with a comment describing the same trap.
        .onTapGesture { onSelect() }
        .simultaneousGesture(TapGesture(count: 2).onEnded { onBeginRename() })
        .ainkradContextMenu([
            AinkradMenuItem(title: "Rename", systemName: "pencil") { onBeginRename() },
            AinkradMenuItem(title: "Close", systemName: "xmark", isDestructive: true) { onClose() },
        ])
        .help(isRenaming ? "" : title)
        .animation(reduceMotion ? nil : .easeOut(duration: skin.motion.durations.d0_12), value: hovering)
        // Faster than the pane's 170ms arrival, so the tab confirms the click
        // first and the pane follows it. The other order — pane first, tab
        // catching up — is what makes a tab bar feel laggy even when it isn't.
        .animation(reduceMotion ? nil : .easeOut(duration: skin.motion.fast), value: isActive)
    }

    private func commit() {
        guard isRenaming else { return }
        onRename(draft)
        onEndRename()
    }
}
