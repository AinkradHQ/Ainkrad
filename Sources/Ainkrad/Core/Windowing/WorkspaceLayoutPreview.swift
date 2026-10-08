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

        var showsNames: Bool { self == .feature }
    }

    let workspace: Workspace
    let registry: BuiltInAppRegistry
    let style: Style

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradSkin) private var skin

    /// Colours come from `hostSkin`, which carries the user's custom accent;
    /// every scalar comes from the environment's skin.
    private var tokens: AinkradSkin { environment.themeManager.hostSkin }
    private var layout: TileLayout { workspace.tileLayout }

    // The style's metrics: the feature preview is drawn at full detail, the
    // row thumbnail at hairline scale.
    private var paneCornerCut: CGFloat { style == .feature ? skin.cut.c6 : skin.cut.c2 }
    private var outerCornerCut: CGFloat { style == .feature ? skin.radius.sm : skin.cut.c4 }
    private var gap: CGFloat { style == .feature ? skin.size.s4 : skin.size.s1_5 }
    private var tabStripHeight: CGFloat { style == .feature ? skin.size.s14 : skin.size.s5 }

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
            skin.shape(cut: outerCornerCut)
                .fill(tokens.color(\.background).opacity(skin.opacity.o35))
        )
        .clipShape(skin.shape(cut: outerCornerCut))
        .overlay(
            skin.shape(cut: outerCornerCut)
                .strokeBorder(tokens.color(\.foreground).opacity(skin.opacity.o10), lineWidth: 1)
        )
    }

    /// An empty workspace is a real state, not a missing preview — the dashed
    /// frame says "nothing here yet" rather than "failed to draw".
    private var emptyState: some View {
        skin.shape(cut: outerCornerCut)
            .strokeBorder(
                tokens.color(\.foreground).opacity(skin.opacity.o18),
                style: StrokeStyle(lineWidth: 1, dash: [3, 2])
            )
            .overlay {
                if style.showsNames {
                    Text("empty")
                        .font(AinkradFont.mono(10))
                        .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o35))
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
                        width: max(unit.width * size.width - gap, 1),
                        height: max(unit.height * size.height - gap, 1)
                    )
                    .offset(
                        x: unit.minX * size.width + gap / 2,
                        y: unit.minY * size.height + gap / 2
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
        let stripHeight = tabStripHeight

        return VStack(spacing: gap) {
            HStack(spacing: gap) {
                ForEach(layout.blocks) { block in
                    let isActive = block.id == focused.id
                    skin.shape(cut: paneCornerCut)
                        .fill(
                            isActive
                                ? tokens.color(\.accentPrimary).opacity(skin.opacity.o50)
                                : tokens.color(\.surfaceElevated).opacity(skin.opacity.o70)
                        )
                        .frame(height: stripHeight)
                        .overlay {
                            if style.showsNames, isActive {
                                Text(title(for: block))
                                    .font(AinkradFont.mono(8, weight: .medium))
                                    .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o90))
                                    .lineLimit(1)
                                    .padding(.horizontal, skin.size.s3)
                            }
                        }
                }
            }
            .frame(height: stripHeight)

            paneCell(focused)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(gap)
        .frame(width: size.width, height: size.height)
    }

    /// One pane in the preview: the app's tile, its name at feature size, and
    /// the focused pane's accent border — the same signal the real pane wears.
    private func paneCell(_ block: Block) -> some View {
        let isFocused = block.id == layout.focusedBlockID && layout.blocks.count > 1
        return skin.shape(cut: paneCornerCut)
            .fill(tokens.color(\.surface).opacity(skin.opacity.o75))
            .overlay(
                skin.shape(cut: paneCornerCut)
                    .strokeBorder(
                        isFocused
                            ? tokens.color(\.accentPrimary).opacity(skin.opacity.o70)
                            : tokens.color(\.foreground).opacity(skin.opacity.o12),
                        lineWidth: 1
                    )
            )
            .overlay { paneContents(block) }
    }

    @ViewBuilder
    private func paneContents(_ block: Block) -> some View {
        if style.showsNames {
            VStack(spacing: skin.spacing.xs) {
                NeonAppTile(symbol: icon(for: block), tokens: tokens, size: skin.size.s22)
                Text(title(for: block))
                    .font(AinkradFont.display(10, weight: .medium))
                    .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o75))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, skin.spacing.xs)

                // Which ⌥N reaches this pane. Three unnamed terminals otherwise
                // read as three cells all labelled "Rune", so the preview showed
                // you the shape of the workspace but not which pane was which.
                if let shortcut = shortcut(for: block) {
                    Text(shortcut)
                        .font(AinkradFont.mono(9, weight: .medium))
                        .foregroundStyle(tokens.color(\.accentSecondary).opacity(skin.opacity.o70))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        } else {
            // At row size a name would be unreadable, so the tile alone carries
            // the identity — which is still infinitely more than a blank fill.
            NeonAppTile(symbol: icon(for: block), tokens: tokens, size: skin.size.s12)
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
