import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// A true miniature of a workspace: its real pane arrangement, drawn from the
/// layout's unit-space frames, with each pane carrying the app it holds.
///
/// ## Why this replaced the old thumbnail
///
/// The Workspace Overview's only spatial cue used to be a 42×30 rectangle of
/// flat accent fills — the arrangement with every trace of identity stripped
/// out. Two workspaces each holding two side-by-side panes were pixel-identical,
/// however different their contents, so the one question the screen exists to
/// answer ("which workspace is this?") could only be answered by reading the
/// name. That makes the preview decoration.
///
/// A workspace is recognised by what is IN it. So each pane now shows its app's
/// neon tile, and at feature size its name too; the focused pane wears the
/// accent border it wears in the real layout; and a workspace in Focus Mode is
/// drawn the way it actually looks — a tab strip above one full-canvas pane —
/// rather than as the split tree it happens to be stored as.
struct WorkspaceLayoutPreview: View {
    /// How much room the preview has, and therefore how much it can say.
    enum Style {
        /// Row-sized: arrangement plus app tiles, no text.
        case thumbnail
        /// The detail pane's recognition anchor: arrangement, tiles and names.
        case feature

        var paneCornerCut: CGFloat { self == .feature ? 6 : 2 }
        var outerCornerCut: CGFloat { self == .feature ? AinkradRadius.sm : 4 }
        var gap: CGFloat { self == .feature ? 4 : 1.5 }
        var showsNames: Bool { self == .feature }
        var tabStripHeight: CGFloat { self == .feature ? 14 : 5 }
    }

    let workspace: Workspace
    let registry: BuiltInAppRegistry
    let tokens: DesignTokens
    let style: Style

    private var layout: TileLayout { workspace.tileLayout }

    /// Focus Mode only reads as Focus Mode when there is more than one pane —
    /// matching `PaneGeometryResolver`, so the preview never claims a state the
    /// workspace isn't in.
    private var isInFocusMode: Bool {
        workspace.viewMode == .focus && layout.blocks.count > 1
    }

    var body: some View {
        GeometryReader { geo in
            if layout.isEmpty {
                emptyState
            } else if isInFocusMode {
                focusModePreview(in: geo.size)
            } else {
                splitPreview(in: geo.size)
            }
        }
        .background(
            ChamferShape(cut: style.outerCornerCut)
                .fill(tokens.background.opacity(0.35))
        )
        .clipShape(ChamferShape(cut: style.outerCornerCut))
        .overlay(
            ChamferShape(cut: style.outerCornerCut)
                .strokeBorder(tokens.foreground.opacity(0.1), lineWidth: 1)
        )
    }

    /// An empty workspace is a real state, not a missing preview — the dashed
    /// frame says "nothing here yet" rather than "failed to draw".
    private var emptyState: some View {
        ChamferShape(cut: style.outerCornerCut)
            .strokeBorder(
                tokens.foreground.opacity(0.18),
                style: StrokeStyle(lineWidth: 1, dash: [3, 2])
            )
            .overlay {
                if style.showsNames {
                    Text("empty")
                        .font(AinkradFont.mono(10))
                        .foregroundStyle(tokens.foreground.opacity(0.35))
                }
            }
    }

    /// The split tree, at its real proportions.
    private func splitPreview(in size: CGSize) -> some View {
        let frames = layout.paneFrames()
        return ZStack(alignment: .topLeading) {
            ForEach(layout.blocks) { block in
                let unit = frames[block.id] ?? .zero
                paneCell(block)
                    .frame(
                        width: max(unit.width * size.width - style.gap, 1),
                        height: max(unit.height * size.height - style.gap, 1)
                    )
                    .offset(
                        x: unit.minX * size.width + style.gap / 2,
                        y: unit.minY * size.height + style.gap / 2
                    )
            }
        }
    }

    /// Focus Mode as the user sees it: tabs above one full pane. Drawing the
    /// underlying split tree here would show a workspace the user is looking at
    /// as tabs as though it were tiled, which is a preview that lies.
    private func focusModePreview(in size: CGSize) -> some View {
        let focusedID = layout.focusedBlockID
        let focused = layout.blocks.first { $0.id == focusedID } ?? layout.blocks[0]
        let stripHeight = style.tabStripHeight

        return VStack(spacing: style.gap) {
            HStack(spacing: style.gap) {
                ForEach(layout.blocks) { block in
                    let isActive = block.id == focused.id
                    ChamferShape(cut: style.paneCornerCut)
                        .fill(
                            isActive
                                ? tokens.accentPrimary.opacity(0.5)
                                : tokens.surfaceElevated.opacity(0.7)
                        )
                        .frame(height: stripHeight)
                        .overlay {
                            if style.showsNames, isActive {
                                Text(title(for: block))
                                    .font(AinkradFont.mono(8, weight: .medium))
                                    .foregroundStyle(tokens.foreground.opacity(0.9))
                                    .lineLimit(1)
                                    .padding(.horizontal, 3)
                            }
                        }
                }
            }
            .frame(height: stripHeight)

            paneCell(focused)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(style.gap)
        .frame(width: size.width, height: size.height)
    }

    /// One pane in the preview: the app's tile, its name at feature size, and
    /// the focused pane's accent border — the same signal the real pane wears.
    private func paneCell(_ block: Block) -> some View {
        let isFocused = block.id == layout.focusedBlockID && layout.blocks.count > 1
        return ChamferShape(cut: style.paneCornerCut)
            .fill(tokens.surface.opacity(0.75))
            .overlay(
                ChamferShape(cut: style.paneCornerCut)
                    .strokeBorder(
                        isFocused ? tokens.accentPrimary.opacity(0.7) : tokens.foreground.opacity(0.12),
                        lineWidth: 1
                    )
            )
            .overlay { paneContents(block) }
    }

    @ViewBuilder
    private func paneContents(_ block: Block) -> some View {
        if style.showsNames {
            VStack(spacing: 4) {
                NeonAppTile(symbol: icon(for: block), tokens: tokens, size: 22)
                Text(title(for: block))
                    .font(AinkradFont.display(10, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 4)

                // Which ⌥N reaches this pane. Three unnamed terminals otherwise
                // read as three cells all labelled "Rune", so the preview showed
                // you the shape of the workspace but not which pane was which.
                if let shortcut = shortcut(for: block) {
                    Text(shortcut)
                        .font(AinkradFont.mono(9, weight: .medium))
                        .foregroundStyle(tokens.accentSecondary.opacity(0.7))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        } else {
            // At row size a name would be unreadable, so the tile alone carries
            // the identity — which is still infinitely more than a blank fill.
            NeonAppTile(symbol: icon(for: block), tokens: tokens, size: 12)
        }
    }

    private func app(for block: Block) -> RegisteredApp? {
        registry.allApps.first { $0.id == block.appID }
    }

    private func icon(for block: Block) -> String {
        app(for: block)?.icon ?? "app"
    }

    /// The name the user knows the pane by — its renamed tab title if it has
    /// one, else the app's.
    private func title(for block: Block) -> String {
        block.displayTitle(appName: app(for: block)?.displayName)
    }

    /// The ⌥N that focuses this pane, by its position in the workspace.
    private func shortcut(for block: Block) -> String? {
        guard let ordinal = layout.blocks.firstIndex(where: { $0.id == block.id }) else { return nil }
        return PaneShortcut.label(forOrdinal: ordinal)
    }
}
