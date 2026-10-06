import AinkradAppKit
import AinkradAppKitUI
import SwiftUI

/// The always-present scoped search field, sitting in the breadcrumb row.
///
/// Searches recursively BELOW the pane's current folder, live. ⌥F focuses it;
/// ⌘F is the separate global palette, because "find that file" is usually a
/// question about the whole machine while this one is explicitly "find it under
/// here". (⌥F rather than ⌘⇧F: that chord is claimed above the app and never
/// arrives — see `HoardKeyMonitor`.)
///
/// Permanently visible rather than summoned: scoped search is the common case,
/// and hiding it behind a keystroke means most people never find it.
struct HoardFilterField: View {
    @Bindable var search: HoardSearchStore

    /// The pane's ONE focus state — not a private one. See `HoardFocusTarget`.
    var focus: FocusState<HoardFocusTarget?>.Binding

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: AinkradSpacing.xs) {
            Image(systemName: search.isScopedSearching ? "ellipsis" : "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(theme.foreground.opacity(search.isScoped ? 0.8 : 0.4))

            TextField("Search here  ⌥F", text: $search.scopedText)
                .textFieldStyle(.plain)
                .font(AinkradFontResolver.font(.caption, typography: typo))
                .focused(focus, equals: .search)
                .frame(width: 150)
                .onExitCommand {
                    search.clearScoped()
                    focus.wrappedValue = .list
                }

            if search.isScoped {
                AinkradIconButton(systemName: "xmark.circle.fill", size: skin.size.s14, tooltip: "Clear search") {
                    search.clearScoped()
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, AinkradSpacing.sm)
        .padding(.vertical, 3)
        .background(
            ChamferShape(cut: 4)
                .fill(theme.foreground.opacity(search.isScoped ? 0.10 : 0.06))
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: search.isScoped)
        .onTapGesture { focus.wrappedValue = .search }
        // A visible focus ring: without it, ⌥F looks like it did nothing even
        // when the caret is sitting in the field.
        .overlay(
            ChamferShape(cut: 4)
                .strokeBorder(
                    theme.accentSecondary.opacity(
                        focus.wrappedValue == .search ? 0.7 : 0), lineWidth: 1)
        )
    }
}
