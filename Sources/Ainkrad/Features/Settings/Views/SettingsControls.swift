import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// Masked API-key entry with a reveal (eye) toggle. Thin adapter over the kit's
/// `AinkradSecureField` (which already carries the reveal toggle + chamfer focus
/// ring). The `tokens` parameter is unused (kit reads `\.ainkradTheme`) but kept
/// so its Sage Connections consumers stay untouched. Never logs or
/// otherwise surfaces the value beyond this field.
struct NeonSecureField: View {
    @Binding var text: String
    let placeholder: String
    let tokens: DesignTokens  // unused adapter param — kit reads \.ainkradTheme

    var body: some View {
        AinkradSecureField(text: $text, placeholder: placeholder)
    }
}

/// The project's standard hover feedback for a list row that is otherwise
/// inert until it is selected: the same `surfaceElevated` wash the kit's
/// collapsible group headers use, plus the same accent hairline `SettingsRow`
/// uses — on the same 0.12s ease-out, gated on reduce-motion. Both are drawn
/// because a row with no fill of its own (the sidebar) reads the wash, while
/// a row that already has one (the palette) reads the hairline.
///
/// It is a `ViewModifier` rather than inline `@State` because the sidebar and
/// palette rows are built by *functions* on their parent view — a `@State`
/// there would be one flag shared by every row, so hovering one would light
/// them all. Each application of this modifier is its own view with its own
/// state.
///
/// Suppressed while `isActive` (selected / keyboard-highlighted) so the hover
/// wash never fights the accent selection fill drawn beneath it.
struct SettingsRowHover: ViewModifier {
    @Environment(\.ainkradTheme) private var tokens
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    let isActive: Bool
    @State private var isHovered = false

    private var shows: Bool { isHovered && !isActive }

    func body(content: Content) -> some View {
        content
            .background(
                ChamferShape(cut: AinkradRadius.md)
                    .fill(tokens.surfaceElevated.opacity(shows ? 0.5 : 0))
            )
            .overlay(
                ChamferShape(cut: AinkradRadius.md)
                    .strokeBorder(tokens.accentPrimary.opacity(shows ? 0.3 : 0), lineWidth: 1)
            )
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
    }
}

extension View {
    /// See `SettingsRowHover`.
    func settingsRowHover(isActive: Bool) -> some View {
        modifier(SettingsRowHover(isActive: isActive))
    }
}
