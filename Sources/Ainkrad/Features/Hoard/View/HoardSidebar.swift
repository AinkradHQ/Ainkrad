import SwiftUI
import AinkradAppKit
import AinkradAppKitUI

/// The roots list. Selection follows the active tab's directory rather than
/// holding its own state — otherwise navigating by any other means would
/// leave the sidebar highlighting the wrong row.
struct HoardSidebar: View {
    let sections: [SidebarSection]
    let currentDirectory: URL
    let iconSize: CGFloat
    let rowPadding: CGFloat
    let onSelect: (SidebarRoot) -> Void
    /// Unpin a favourite. Only offered on removable sections.
    let onRemove: (SidebarRoot) -> Void

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradTypography) private var typo

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(sections) { section in
                    if let title = section.title {
                        Text(title.uppercased())
                            .font(AinkradFontResolver.font(.caption, weight: .medium,
                                                           typography: typo))
                            .foregroundStyle(theme.foreground.opacity(0.4))
                            .padding(.horizontal, AinkradSpacing.sm)
                            .padding(.top, AinkradSpacing.md)
                            .padding(.bottom, 2)
                    }
                    ForEach(section.roots) { root in
                        let row = SidebarRootRow(
                            root: root,
                            isSelected: root.url == currentDirectory,
                            iconSize: iconSize,
                            rowPadding: rowPadding,
                            onTap: { onSelect(root) }
                        )
                        // Attached ONLY where there is something to offer, so
                        // a standard place does not pop an empty menu. Same
                        // styled menu as the file rows — see `HoardRowMenu`.
                        if section.isRemovable {
                            row.sidebarRootMenu(root: root, onRemove: onRemove)
                        } else {
                            row
                        }
                    }
                }
            }
            .padding(.horizontal, AinkradSpacing.sm)
            .padding(.vertical, AinkradSpacing.sm)
        }
        .frame(width: 164)
    }
}

/// Matches `FileRowView`'s density rather than `AinkradListRow`'s — a sidebar
/// whose rows are twice the height of the list they navigate reads as two
/// unrelated components bolted together.
private struct SidebarRootRow: View {
    let root: SidebarRoot
    let isSelected: Bool
    let iconSize: CGFloat
    let rowPadding: CGFloat
    let onTap: () -> Void

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        HStack(spacing: AinkradSpacing.sm) {
            AinkradIconGlyph(systemName: root.icon, size: iconSize - 1)
                .frame(width: iconSize + 5)
            Text(root.name)
                .font(AinkradFontResolver.font(.body, typography: typo))
                .foregroundStyle(theme.foreground.opacity(isSelected ? 1 : 0.8))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AinkradSpacing.sm)
        .padding(.vertical, rowPadding)
        .background(ChamferShape(cut: 4).fill(fill))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onTap)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: hovering)
    }

    private var fill: Color {
        if isSelected { return theme.accentPrimary.opacity(0.22) }
        if hovering { return theme.foreground.opacity(0.06) }
        return .clear
    }
}
