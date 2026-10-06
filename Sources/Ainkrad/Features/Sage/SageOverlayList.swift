import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// Shared presentation shell for the composer's floating overlays — the
/// `@`-mention list and the `/`-command palette. Both render their rows through
/// this so container padding, the compact empty state, and the keyboard-hint
/// footer live in exactly one place. Presentation-only: no environment reads,
/// no data fetching (mirrors the views it backs).
struct SageOverlayList<Content: View>: View {
    @Environment(\.ainkradSkin) private var skin
    let isEmpty: Bool
    let emptyIcon: String
    let emptyText: String
    @Environment(\.ainkradTheme) private var theme
    var showsHint: Bool = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: skin.spacing.xs) {
            if isEmpty {
                emptyState
            } else {
                content()
                if showsHint { hintFooter }
            }
        }
        .padding(skin.size.s6)
        // The floating-panel window is transparent by design
        // (`AinkradFloatingPanelController` sets it `.clear`/non-opaque), so the
        // content MUST draw its own panel chrome — same chamfer fill + accent
        // stroke + glow the kit's own dropdowns use (`MultiSelectPanelView`).
        // Without this the overlay renders see-through over the transcript.
        .background(ChamferShape(cut: skin.cut.c8).fill(theme.surfaceElevated.opacity(skin.opacity.o97)))
        .overlay(ChamferShape(cut: skin.cut.c8).strokeBorder(theme.accentSecondary.opacity(skin.opacity.o55), lineWidth: 1.25))
        .shadow(color: theme.accentSecondary.opacity(skin.opacity.o35), radius: skin.size.s10, y: 4)
        .frame(minWidth: skin.size.s280)
    }

    /// Compact empty treatment sized for a ~280px floating panel — a single
    /// muted glyph over one muted line. Deliberately NOT `AinkradEmptyState`
    /// (icon + title + message), which is too tall for this panel.
    private var emptyState: some View {
        VStack(spacing: skin.size.s6) {
            Image(systemName: emptyIcon)
                .font(skin.font(AinkradFontToken(sizeKey: "t18", weight: "regular", scaled: false)))
                .foregroundStyle(theme.foreground.opacity(skin.opacity.o40))
            Text(emptyText)
                .font(AinkradFont.display(12))
                .foregroundStyle(theme.foreground.opacity(skin.opacity.o50))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, skin.size.s14)
    }

    /// Muted keyboard-hint row (no separator line — Cardinal HUD rule).
    private var hintFooter: some View {
        Text("↑↓ navigate · ↵ select · esc dismiss")
            .font(AinkradFont.display(10))
            .foregroundStyle(theme.foreground.opacity(skin.opacity.o35))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, skin.size.s6)
            .padding(.top, skin.size.s2)
    }
}
