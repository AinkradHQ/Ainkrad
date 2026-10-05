import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// Shared presentation shell for the composer's floating overlays — the
/// `@`-mention list and the `/`-command palette. Both render their rows through
/// this so container padding, the compact empty state, and the keyboard-hint
/// footer live in exactly one place. Presentation-only: no environment reads,
/// no data fetching (mirrors the views it backs).
struct SageOverlayList<Content: View>: View {
    let isEmpty: Bool
    let emptyIcon: String
    let emptyText: String
    let tokens: DesignTokens
    var showsHint: Bool = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isEmpty {
                emptyState
            } else {
                content()
                if showsHint { hintFooter }
            }
        }
        .padding(6)
        // The floating-panel window is transparent by design
        // (`AinkradFloatingPanelController` sets it `.clear`/non-opaque), so the
        // content MUST draw its own panel chrome — same chamfer fill + accent
        // stroke + glow the kit's own dropdowns use (`MultiSelectPanelView`).
        // Without this the overlay renders see-through over the transcript.
        .background(ChamferShape(cut: 8).fill(tokens.surfaceElevated.opacity(0.97)))
        .overlay(ChamferShape(cut: 8).strokeBorder(tokens.accentSecondary.opacity(0.55), lineWidth: 1.25))
        .shadow(color: tokens.accentSecondary.opacity(0.35), radius: 10, y: 4)
        .frame(minWidth: 280)
    }

    /// Compact empty treatment sized for a ~280px floating panel — a single
    /// muted glyph over one muted line. Deliberately NOT `AinkradEmptyState`
    /// (icon + title + message), which is too tall for this panel.
    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: emptyIcon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(tokens.foreground.opacity(0.4))
            Text(emptyText)
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    /// Muted keyboard-hint row (no separator line — Cardinal HUD rule).
    private var hintFooter: some View {
        Text("↑↓ navigate · ↵ select · esc dismiss")
            .font(AinkradFont.display(10))
            .foregroundStyle(tokens.foreground.opacity(0.35))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.top, 2)
    }
}
