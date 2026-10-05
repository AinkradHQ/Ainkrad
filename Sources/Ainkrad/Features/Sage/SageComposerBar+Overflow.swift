import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// Overflow panel for `SageComposerBar` (Wave 3 Task 7).
///
/// Collapses the two low-traffic utilities (Usage & cost, Export) behind a
/// single `•••` control — a Cardinal HUD floating panel, never a native
/// Menu. Runs and Schedules stay visible in the strip (high-traffic).
///
/// Wave 3b: the panel chrome now matches `AinkradSelect`'s
/// `SearchableSelectPanelView.optionsPanel` exactly (chamfer fill/border/
/// shadow) so it doesn't read as unstyled next to the real dropdown panels.
extension SageComposerBar {
    var overflowTrigger: some View {
        AinkradIconButton(systemName: "ellipsis", size: SageComposerBar.controlHeight, tooltip: "More") {
            isOverflowVisible.toggle()
        }
        .ainkradFloatingPanel(isPresented: $isOverflowVisible, maxHeight: 170) {
            VStack(alignment: .leading, spacing: 0) {
                OverflowRow(icon: "gauge.with.dots.needle.67percent", title: "Usage & cost", tokens: tokens) {
                    isOverflowVisible = false
                    isUsageDashboardPresented = true
                }
                OverflowRow(icon: "square.and.arrow.up", title: "Export…", tokens: tokens) {
                    isOverflowVisible = false
                    isExportModalPresented = true
                }
                OverflowRow(icon: "link", title: "Share…", tokens: tokens) {
                    isOverflowVisible = false
                    isShareModalPresented = true
                }
            }
            .padding(AinkradSpacing.xs)
            .background(ChamferShape(cut: 8).fill(tokens.surfaceElevated.opacity(0.97)))
            .overlay(ChamferShape(cut: 8).strokeBorder(tokens.accentSecondary.opacity(0.55), lineWidth: 1.25))
            .shadow(color: tokens.accentSecondary.opacity(0.35), radius: 10, y: 4)
            .frame(minWidth: 160)
        }
    }
}

/// A single overflow-panel row: icon + title, with its own hover highlight.
/// Pulled out as a real `View` (rather than a helper method on the
/// extension) because the extension carries no stored state of its own —
/// hover needs a `@State` home.
private struct OverflowRow: View {
    let icon: String
    let title: String
    let tokens: DesignTokens
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: AinkradSpacing.xs) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(tokens.accentSecondary)
                Text(title).font(AinkradFont.display(13)).foregroundStyle(tokens.foreground)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AinkradSpacing.sm)
            .padding(.vertical, AinkradSpacing.xs + 2)
            .background(ChamferShape(cut: 4).fill(isHovered ? tokens.accentSecondary.opacity(0.18) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : AinkradMotion.hover, value: isHovered)
    }
}
