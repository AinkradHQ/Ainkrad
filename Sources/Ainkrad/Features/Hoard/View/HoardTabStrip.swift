import AinkradAppKit
import AinkradAppKitUI
import SwiftUI

/// Per-pane tabs. Hidden entirely when there is only one — a lone tab is
/// chrome that earns nothing.
struct HoardTabStrip: View {
    let store: HoardPaneStore

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @Environment(\.ainkradSkin) private var skin
    /// Drives the sliding active-tab highlight. A `matchedGeometryEffect`
    /// namespace so the fill MOVES between tabs instead of popping out of one
    /// and into another.
    @Namespace private var activeTab

    var body: some View {
        if store.tabs.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: skin.size.s2) {
                    ForEach(Array(store.tabs.enumerated()), id: \.element.id) { index, tab in
                        TabChip(
                            title: tab.title,
                            isActive: index == store.activeTabIndex,
                            namespace: activeTab,
                            onSelect: {
                                withAnimation(reduceMotion ? nil : .easeOut(duration: skin.motion.durations.d0_18)) {
                                    store.selectTab(at: index)
                                }
                            },
                            onClose: { store.closeTab(at: index) }
                        )
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, HoardColumnMetrics.headerInset)
                .padding(.top, AinkradSpacing.sm)
            }
        }
    }
}

private struct TabChip: View {
    let title: String
    let isActive: Bool
    let namespace: Namespace.ID
    let onSelect: () -> Void
    let onClose: () -> Void

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @Environment(\.ainkradSkin) private var skin
    @State private var hovering = false

    var body: some View {
        HStack(spacing: AinkradSpacing.xs) {
            Text(title)
                .font(
                    AinkradFontResolver.font(
                        .caption, weight: isActive ? .medium : .regular,
                        typography: typo)
                )
                .foregroundStyle(theme.foreground.opacity(isActive ? skin.opacity.o95 : skin.opacity.o60))
                .lineLimit(1)

            // The close button only takes space on the active or hovered tab,
            // so a row of inactive tabs stays legible instead of being half
            // occupied by ✕ glyphs.
            if isActive || hovering {
                AinkradIconButton(systemName: "xmark", size: skin.size.s14, tooltip: "Close Tab", action: onClose)
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
        }
        .padding(.horizontal, AinkradSpacing.sm)
        .padding(.vertical, skin.size.s4)
        .background {
            if isActive {
                skin.shape(cut: skin.cut.c5)
                    .fill(theme.accentPrimary.opacity(skin.opacity.o20))
                    .matchedGeometryEffect(id: "activeTabFill", in: namespace)
            } else if hovering {
                skin.shape(cut: skin.cut.c5).fill(theme.foreground.opacity(skin.opacity.o06))
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onSelect)
        .animation(reduceMotion ? nil : .easeOut(duration: skin.motion.durations.d0_14), value: hovering)
        .animation(reduceMotion ? nil : .easeOut(duration: skin.motion.durations.d0_18), value: isActive)
    }
}
