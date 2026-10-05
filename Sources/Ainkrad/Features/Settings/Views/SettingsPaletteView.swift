import AinkradAppKit
import AinkradAppKitContract
import AinkradHostRuntime
import SwiftUI

/// The ranked result list that replaces the detail pane while searching.
/// Each row shows the field, where it lives, and its current value — the
/// value is often the whole reason for the search. Composes the kit's
/// `AinkradCommandMenu` (extended with `detail`/`value` slots, keyboard
/// navigation, and an empty-state slot) rather than a bespoke result list.
struct SettingsPaletteView: View {
    let results: [SettingsSearchResult]
    let query: String
    /// The keyboard highlight, owned by `SettingsOverlayView` because the keys
    /// that move it arrive at the SEARCH FIELD in the sidebar — the palette
    /// itself is never focused, so `.onKeyPress` inside it would never fire.
    @Binding var highlight: Int?
    let onSelect: (SettingsPath) -> Void

    /// `AinkradCommandMenu` is keyed by item, so it's driven by `SettingsPath`
    /// (Hashable) with the matching `SettingsSearchResult` looked up per row —
    /// `SettingsSearchResult` itself carries a `score: Int` that makes it
    /// unsuitable as a stable Hashable identity across re-searches.
    @State private var selection: SettingsPath?

    private func result(for path: SettingsPath) -> SettingsSearchResult? {
        results.first { $0.path == path }
    }

    var body: some View {
        ScrollView {
            AinkradCommandMenu(
                items: results.map(\.path),
                selection: $selection,
                icon: { _ in "magnifyingglass" },
                label: { result(for: $0)?.label ?? "" },
                detail: { result(for: $0)?.breadcrumb },
                value: { result(for: $0)?.valueDescription },
                uppercased: false,
                emptyState: {
                    AnyView(
                        AinkradEmptyState(
                            icon: "magnifyingglass",
                            title: "No settings match \u{201C}\(query)\u{201D}",
                            message: "Try a shorter word, or the name of the app the setting belongs to.")
                    )
                },
                highlight: $highlight
            )
            .padding(AinkradSpacing.lg)
        }
        .scrollContentBackground(.hidden)
        .onChange(of: selection) { _, newValue in
            guard let newValue else { return }
            onSelect(newValue)
        }
        .onChange(of: query) { _, _ in selection = nil }
    }
}
