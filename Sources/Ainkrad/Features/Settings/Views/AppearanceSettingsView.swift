import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// The Ainkrad → Appearance section: a theme picker bound to `ThemeManager`.
/// Selecting a theme applies tokens immediately, with no Save button. The
/// Dock icon is a separate, independent manual preference — see the App Icon
/// section (`AppIconSettingsView`) — and is not affected by theme changes.
/// See Theme System.md and ADR-0006. Theme cards preview each theme's accent
/// ramp inside targeting brackets.
struct AppearanceSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 10)]

    var body: some View {
        let tokens = environment.themeManager.tokens

        VStack(alignment: .leading, spacing: 14) {
            AinkradSettingsPanel(
                title: "Theme",
                hint: "The whole workspace re-tints — window, islands, and the sky behind it."
            ) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Theme.allCases, id: \.self) { theme in
                        themeCard(theme, tokens: tokens)
                    }
                }
            }

            AinkradSettingsPanel(
                title: "Accent",
                hint: "Used for anything live: selection, focus, the things that are "
                    + "currently doing something."
            ) {
                accentColorRow(tokens: tokens, manager: environment.themeManager)
            }

            AinkradSettingsPanel(
                title: "Typeface and size",
                hint: "Every word in the app, including the ones you are reading now."
            ) {
                VStack(alignment: .leading, spacing: 9) {
                    AinkradCaptionedRow("Size") {
                        segmented(UIFontScale.allCases,
                                  selected: environment.themeManager.uiFontScale,
                                  tokens: tokens,
                                  title: fontScaleTitle,
                                  action: { environment.themeManager.setFontScale($0) })
                    }
                    AinkradCaptionedRow("Typeface") {
                        segmented(UIFontFamily.allCases,
                                  selected: environment.themeManager.uiFontFamily,
                                  tokens: tokens,
                                  title: fontFamilyTitle,
                                  action: { environment.themeManager.setFontFamily($0) })
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Font family and size")
            }

            AinkradSettingsPanel(
                title: "Motion",
                hint: "Turns off transitions, parallax, blinking cursors, and other animation "
                    + "across Ainkrad. Independent of the macOS system Reduce Motion setting."
            ) {
                AinkradCaptionedRow("Reduce motion") {
                    segmented([true, false],
                              selected: environment.generalSettingsStore.uiReduceMotion,
                              tokens: tokens,
                              title: { $0 ? "On" : "Off" },
                              action: { environment.generalSettingsStore.setUiReduceMotion($0) })
                }
            }

            AinkradSettingsPanel(
                title: "Overlays",
                hint: "Lower opacity — and blur — let the workspace show through the Launcher, "
                    + "Settings, App Store, notifications, and every other overlay."
            ) {
                overlayControls(tokens: tokens)
            }
        }
    }

    // MARK: - Overlays (background opacity + blur)

    private func overlayControls(tokens: DesignTokens) -> some View {
        let store = environment.generalSettingsStore
        return VStack(alignment: .leading, spacing: 9) {
            AinkradCaptionedRow("Opacity") {
                HStack(spacing: 12) {
                    AinkradSlider(
                        value: Binding(
                            get: { store.overlayBackgroundOpacity },
                            set: { store.setOverlayBackgroundOpacity($0) }),
                        in: 0.3...1.0)
                    Text("\(Int(store.overlayBackgroundOpacity * 100))%")
                        .font(AinkradFont.display(11))
                        .foregroundStyle(tokens.foreground.opacity(0.55))
                        .frame(width: 42, alignment: .trailing)
                }
            }
            AinkradCaptionedRow("Blur") {
                segmented([true, false], selected: store.overlayBlurEnabled, tokens: tokens,
                          title: { $0 ? "On" : "Off" },
                          action: { store.setOverlayBlurEnabled($0) })
            }
        }
    }

    private func segmented<T: Hashable>(_ items: [T], selected: T, tokens: DesignTokens,
                                        title: @escaping (T) -> String, action: @escaping (T) -> Void) -> some View {
        // Delegates to the kit segmented control; the imperative `action`
        // write-back rides in the binding's setter. `AinkradSegmentedPicker`
        // self-gates its selection motion, so the former host `.animation`
        // (folded from W7) lives inside the kit now.
        AinkradSegmentedPicker(
            items: items,
            selection: Binding(get: { selected }, set: { action($0) }),
            label: title
        )
    }

    private func fontScaleTitle(_ scale: UIFontScale) -> String {
        switch scale { case .small: return "Small"; case .medium: return "Medium"; case .large: return "Large" }
    }

    private func fontFamilyTitle(_ family: UIFontFamily) -> String {
        switch family {
        case .exo2: return "Exo 2"
        case .jetBrainsMono: return "JetBrains Mono"
        case .system: return "System"
        }
    }

    /// A row of preset accent swatches (one per theme's accent), an
    /// `AinkradColorPicker` HUD well for anything else, and a "Theme default"
    /// toggle that
    /// clears the override so the theme's own accent shows again.
    private func accentColorRow(tokens: DesignTokens, manager: ThemeManager) -> some View {
        let presets = Theme.allCases.map(\.tokens.accentPrimary)

        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                ForEach(Array(presets.enumerated()), id: \.offset) { _, color in
                    accentSwatch(color, tokens: tokens, manager: manager)
                }
                AinkradColorPicker(
                    selection: Binding(
                        get: { manager.accentColorHex.map { Color(hex: $0) } ?? tokens.accentPrimary },
                        set: { manager.setAccentColorHex($0.hexString) }
                    )
                )
                .frame(width: 30, height: 30)
            }

            Button {
                manager.setAccentColorHex(nil)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: manager.accentColorHex == nil ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11))
                    Text("Theme default")
                        .font(AinkradFont.display(11))
                }
                .foregroundStyle(manager.accentColorHex == nil ? tokens.accentSecondary : tokens.foreground.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
    }

    private func accentSwatch(_ color: Color, tokens: DesignTokens,
                              manager: ThemeManager) -> some View {
        let hex = color.hexString ?? ""
        let isSelected = AccentSelection.isSelected(
            swatchHex: hex,
            overrideHex: manager.accentColorHex,
            themeAccentHex: manager.currentTheme.tokens.accentPrimary.hexString ?? "")

        return Button {
            manager.setAccentColorHex(hex)
        } label: {
            ChamferShape(cut: 7)
                .fill(color)
                .frame(width: 30, height: 30)
                .overlay(
                    ChamferShape(cut: 7).strokeBorder(
                        isSelected ? tokens.foreground.opacity(0.95) : .white.opacity(0.16),
                        lineWidth: isSelected ? 2 : 1))
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .opacity(isSelected ? 1 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func themeCard(_ theme: Theme, tokens: DesignTokens) -> some View {
        let isSelected = environment.themeManager.currentTheme == theme
        let themeTokens = theme.tokens

        return Button {
            environment.themeManager.setTheme(theme)
        } label: {
            HStack(spacing: 11) {
                // Live preview of this theme's accent ramp.
                ChamferShape(cut: 7)
                    .fill(
                        LinearGradient(
                            colors: [themeTokens.accentPrimary, themeTokens.accentSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30, height: 30)
                    .overlay(
                        ChamferShape(cut: 7)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: themeTokens.accentPrimary.opacity(isSelected ? 0.6 : 0), radius: 8)

                Text(theme.displayName)
                    .font(AinkradFont.display(13, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(isSelected ? 0.95 : 0.7))

                Spacer(minLength: 4)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? tokens.accentSecondary : tokens.foreground.opacity(0.25))
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                ChamferShape(cut: AinkradRadius.md)
                    .fill(isSelected ? tokens.accentPrimary.opacity(0.13) : tokens.surfaceElevated.opacity(0.5))
            )
            .overlay(
                ChamferShape(cut: AinkradRadius.md)
                    .strokeBorder(tokens.accentPrimary.opacity(isSelected ? 0.4 : 0.15), lineWidth: 1)
            )
            .overlay(
                TargetingBrackets(length: 9)
                    .stroke(isSelected ? tokens.accentSecondary.opacity(0.9) : .clear, lineWidth: 1.4)
                    .padding(1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isSelected)
    }
}

