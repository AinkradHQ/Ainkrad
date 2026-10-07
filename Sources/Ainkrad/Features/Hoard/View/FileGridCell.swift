import AinkradAppKit
import AinkradAppKitUI
import SwiftUI

/// One grid cell. Shares `FileRowView`'s cursor/selection semantics — a
/// leading accent for the cursor, a filled background for selection — so
/// switching presentation doesn't change what the states mean.
struct FileGridCell: View {
    let entry: FileEntry
    let isCursor: Bool
    let isSelected: Bool
    let iconSize: CGFloat
    let onTap: () -> Void
    let onDoubleTap: () -> Void

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @Environment(\.ainkradSkin) private var skin
    @State private var hovering = false

    var body: some View {
        VStack(spacing: AinkradSpacing.xs) {
            AinkradIconGlyph(systemName: iconName(for: entry), size: iconSize)
                .opacity(entry.isSymlink ? skin.opacity.o60 : 1)
            Text(entry.name)
                .font(AinkradFontResolver.font(.caption, typography: typo))
                .foregroundStyle(theme.foreground.opacity(skin.opacity.o90))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AinkradSpacing.sm)
        .padding(.horizontal, AinkradSpacing.xs)
        .background(ChamferShape(cut: skin.cut.c6).fill(fill))
        .overlay(
            ChamferShape(cut: skin.cut.c6)
                .strokeBorder(theme.accentSecondary, lineWidth: isCursor ? 1.5 : 0)
        )
        .opacity(entry.isHidden ? skin.opacity.o55 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onTap)
        .simultaneousGesture(TapGesture(count: 2).onEnded { onDoubleTap() })
        .animation(reduceMotion ? nil : .easeOut(duration: skin.motion.durations.d0_12), value: hovering)
    }

    private var fill: Color {
        if isSelected { return theme.accentPrimary.opacity(skin.opacity.o22) }
        if hovering { return theme.foreground.opacity(skin.opacity.o06) }
        return .clear
    }
}
