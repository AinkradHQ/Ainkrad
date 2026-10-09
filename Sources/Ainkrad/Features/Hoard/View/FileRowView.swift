import AinkradAppKit
import AinkradAppKitUI
import SwiftUI

/// One file row.
///
/// Deliberately NOT built on `AinkradListRow`: that component is tuned for
/// settings lists (title + subtitle, generous padding), and a file manager's
/// core job is scanning hundreds of rows at a glance. This keeps the kit's
/// visual language — chamfer fill, leading accent bar, hover scan, theme tint,
/// resolved typography — at a density the list can actually use.
struct FileRowView: View {
    let entry: FileEntry
    /// Where the keyboard is. Drawn as a leading accent bar.
    let isCursor: Bool
    /// Whether the row is part of the selection. Drawn as a filled background.
    /// Separate from `isCursor` on purpose: you move the cursor to look and
    /// select to act, and the two must be tellable apart.
    let isSelected: Bool
    let now: Date
    let iconSize: CGFloat
    let rowPadding: CGFloat
    let showMetadata: Bool
    /// Git state for this row, or `nil` outside a repo / when clean.
    let gitStatus: GitFileStatus?
    let isIgnored: Bool
    /// Marked by ⌘X and not yet pasted — dimmed so the pending move is visible.
    let isCut: Bool
    let onTap: () -> Void
    let onDoubleTap: () -> Void

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @Environment(\.ainkradStatusColors) private var statusColors
    @Environment(\.ainkradSkin) private var skin
    @State private var hovering = false

    var body: some View {
        HStack(spacing: AinkradSpacing.sm) {
            AinkradIconGlyph(systemName: iconName(for: entry), size: iconSize)
                .opacity(entry.isSymlink ? skin.opacity.o60 : 1)
                .frame(width: iconSize + 5)

            Text(entry.name)
                .font(AinkradFontResolver.font(.body, typography: typo))
                .foregroundStyle(theme.foreground)
                .lineLimit(1)
                .truncationMode(.middle)

            // Git state sits AFTER the name: it annotates the file, and a
            // leading gutter pushed every icon rightwards and read as a
            // bullet-point list rather than a status.
            if let gitStatus {
                Image(systemName: gitStatus.glyph)
                    .font(.system(size: iconSize * 0.5))  // design-lint: allow font-size kit-gap gitGlyphRatio
                    .foregroundStyle(color(for: gitStatus))
                    .help(gitStatusLabel(gitStatus))
            }

            Spacer(minLength: AinkradSpacing.md)

            if showMetadata {
                Text(formattedSize(entry.size, isDirectory: entry.isDirectory))
                    .frame(width: HoardColumnMetrics.sizeWidth, alignment: .trailing)
                Text(formattedDate(entry.modified, now: now))
                    .frame(width: HoardColumnMetrics.modifiedWidth, alignment: .trailing)
            }
        }
        .font(AinkradFontResolver.font(.caption, typography: typo))
        .foregroundStyle(theme.foreground.opacity(skin.opacity.o50))
        .monospacedDigit()
        .padding(.horizontal, AinkradSpacing.sm)
        .padding(.vertical, rowPadding)
        .background(skin.shape(cut: skin.cut.c4).fill(rowFill))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(theme.accentSecondary)
                .frame(width: isCursor ? 2 : 0)
        }
        // Hidden AND ignored entries render dimmed when shown, so ⌘. reads as
        // "reveal", not "add more identical rows".
        .opacity(isCut ? skin.opacity.o40 : (entry.isHidden || isIgnored ? skin.opacity.o55 : 1))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // Single tap fires IMMEDIATELY; the double-tap runs alongside it as a
        // simultaneous gesture. Declaring `.onTapGesture(count: 2)` ahead of a
        // single-tap handler makes SwiftUI wait out the double-click interval
        // before delivering the single tap — which is exactly why clicking
        // felt slow and unresponsive.
        .onTapGesture(perform: onTap)
        .simultaneousGesture(TapGesture(count: 2).onEnded { onDoubleTap() })
        .animation(reduceMotion ? nil : .easeOut(duration: skin.motion.durations.d0_12), value: hovering)
        .animation(reduceMotion ? nil : .easeOut(duration: skin.motion.durations.d0_12), value: isSelected)
        .animation(reduceMotion ? nil : .easeOut(duration: skin.motion.durations.d0_12), value: isCursor)
    }

    private func gitStatusLabel(_ status: GitFileStatus) -> String {
        switch status {
        case .staged: return "Staged"
        case .modified: return "Modified"
        case .added: return "Added"
        case .deleted: return "Deleted"
        case .renamed: return "Renamed"
        case .untracked: return "Untracked"
        case .ignored: return "Ignored"
        case .conflicted: return "Conflicted"
        }
    }

    /// Status colours come from the kit's semantic palette, never hardcoded.
    private func color(for status: GitFileStatus) -> Color {
        switch status {
        case .conflicted, .deleted: return statusColors.danger
        case .modified, .staged, .renamed: return statusColors.warning
        case .added: return statusColors.success
        case .untracked: return theme.foreground.opacity(skin.opacity.o45)
        case .ignored: return theme.foreground.opacity(skin.opacity.o30)
        }
    }

    private var rowFill: Color {
        if isSelected { return theme.accentPrimary.opacity(skin.opacity.o22) }
        if hovering { return theme.foreground.opacity(skin.opacity.o06) }
        return .clear
    }
}
