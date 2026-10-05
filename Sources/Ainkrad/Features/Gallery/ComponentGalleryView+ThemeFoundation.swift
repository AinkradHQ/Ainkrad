#if DEBUG
import AppKit
import SwiftUI
import AinkradAppKit

/// Epic 4 promotions: rail item, corner brackets, brand chevron, row
/// background, overlay chrome, command field. Every size and color is read
/// from the skin or an AppKit component; nothing here owns a literal.
extension ComponentGalleryView {
    var themeFoundationSection: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(
                title: "Theme Foundation",
                subtitle: "Rail item, corner brackets, brand chevron, row background, overlay chrome, command field")
            GalleryRailRow()
            GalleryBracketsAndChevronRow()
            GalleryRowBackgroundSamples()
            GalleryOverlayChromeRow()
            GalleryCommandFieldSample()
        }
    }
}

private struct GalleryRailRow: View {
    @Environment(\.ainkradSkin) private var skin
    @Namespace private var slide

    var body: some View {
        HStack(alignment: .top, spacing: AinkradSpacing.lg) {
            VStack(spacing: AinkradSpacing.sm) {
                AinkradRailItem(systemName: "bubble.left.fill", help: "Selected", isSelected: true, action: nil)
                AinkradRailItem(systemName: "bell.fill", help: "Unread 3", isSelected: false, unread: 3, action: nil)
                AinkradRailItem(systemName: "tray.fill", help: "Unread 120", isSelected: false, unread: 120, action: nil)
                AinkradRailItem(
                    systemName: "moon.fill", help: "Muted", isSelected: false, isDimmed: true,
                    cornerSymbol: "speaker.slash.fill", action: nil)
            }
            .padding(.vertical, AinkradSpacing.sm)
            .frame(width: skin.size.s60)

            VStack(spacing: AinkradSpacing.sm) {
                AinkradRailItem(
                    systemName: "square.grid.2x2", help: "Sliding, selected", isSelected: true,
                    selectionNamespace: slide, action: nil)
                AinkradRailItem(
                    systemName: "gearshape", help: "Sliding, rest", isSelected: false,
                    selectionNamespace: slide, action: nil)
            }
            .padding(.vertical, AinkradSpacing.sm)
            .frame(width: skin.size.s60)
        }
    }
}

private struct GalleryBracketsAndChevronRow: View {
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let accent = skin.color(skin.palette.accentSecondary)
        HStack(spacing: AinkradSpacing.lg) {
            ForEach([7, 9, 13], id: \.self) { length in
                AinkradCornerBrackets(length: length)
                    .stroke(accent, lineWidth: skin.size.s1)
                    .frame(width: skin.size.s60, height: skin.size.s44)
            }
            AinkradBrandChevron()
                .fill(accent)
                .frame(width: skin.size.s16, height: skin.size.s14)
                .shadow(color: accent.opacity(skin.opacity.o90), radius: skin.size.s6)
        }
    }
}

private struct GalleryRowBackgroundSamples: View {
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(spacing: AinkradSpacing.xs) {
            sample("Rest", selected: false, hovered: false)
            sample("Hovered", selected: false, hovered: true)
            sample("Selected", selected: true, hovered: false)
        }
        .frame(maxWidth: skin.size.s320)
    }

    private func sample(_ title: String, selected: Bool, hovered: Bool) -> some View {
        AinkradCaption(title)
            .padding(AinkradSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ainkradRowBackground(isSelected: selected, isHovered: hovered)
    }
}

private struct GalleryOverlayChromeRow: View {
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: AinkradSpacing.lg) {
            panel("withinWindow", blending: .withinWindow)
            panel("behindWindow", blending: .behindWindow)
        }
    }

    private func panel(_ title: String, blending: NSVisualEffectView.BlendingMode) -> some View {
        AinkradCaption(title)
            .padding(AinkradSpacing.lg)
            .frame(width: skin.size.s160, height: skin.size.s80)
            .ainkradOverlayChrome(backgroundOpacity: skin.chrome.overlay.backgroundOpacity, blurEnabled: true, blending: blending)
    }
}

private struct GalleryCommandFieldSample: View {
    @Environment(\.ainkradSkin) private var skin
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        AinkradCommandField(
            "Type a command", text: $text, focus: $focused,
            onArrow: { _ in false }, onSubmit: {}, onEscape: {}
        )
        .frame(maxWidth: skin.size.s400)
    }
}
#endif
