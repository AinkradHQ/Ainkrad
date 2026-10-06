import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// Overflow panel for `SageComposerBar` (Wave 3 Task 7). Its rows are the
/// kit's `AinkradCommandMenu`.
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
            AinkradCommandMenu(
                items: OverflowItem.allCases,
                selection: Binding(get: { nil }, set: { if let item = $0 { openOverflowItem(item) } }),
                icon: \.icon, label: \.title, uppercased: false)
            .padding(AinkradSpacing.xs)
            .background(ChamferShape(cut: 8).fill(theme.surfaceElevated.opacity(0.97)))
            .overlay(ChamferShape(cut: 8).strokeBorder(theme.accentSecondary.opacity(0.55), lineWidth: 1.25))
            .shadow(color: theme.accentSecondary.opacity(0.35), radius: 10, y: 4)
            .frame(minWidth: 160)
        }
    }

    /// Closes the panel and presents the chosen utility's modal.
    private func openOverflowItem(_ item: OverflowItem) {
        isOverflowVisible = false
        switch item {
        case .usage: isUsageDashboardPresented = true
        case .export: isExportModalPresented = true
        case .share: isShareModalPresented = true
        }
    }
}

/// The `•••` panel's utilities, in display order.
private enum OverflowItem: CaseIterable, Hashable {
    case usage, export, share

    var icon: String {
        switch self {
        case .usage: return "gauge.with.dots.needle.67percent"
        case .export: return "square.and.arrow.up"
        case .share: return "link"
        }
    }

    var title: String {
        switch self {
        case .usage: return "Usage & cost"
        case .export: return "Export…"
        case .share: return "Share…"
        }
    }
}
