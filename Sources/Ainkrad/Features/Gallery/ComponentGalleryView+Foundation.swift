#if DEBUG
// design-lint: allow-file spacing-literal,radius-literal,opacity-literal,frame-literal gallery-sample — sample content, not chrome
import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Gallery sections: foundation, scales, panel, card, pickers, form controls, state views, section header.
extension ComponentGalleryView {
    // MARK: - Sections

    @ViewBuilder
    func gallerySectionView(named sectionName: String, theme: Theme) -> some View {
        let tokens = HostThemeTokens(from: theme)
        let statusColors = AinkradStatusColors(
            success: theme.skin.color(\.success),
            warning: theme.skin.color(\.warning),
            danger: theme.skin.color(\.danger)
        )
        let typography = AinkradTypography.default

        Group {
            switch sectionName {
            case "foundation": foundationSection
            case "scales": scalesSection
            case "panel": panelSection
            case "card": cardSection
            case "pickers": pickersSection
            case "formControls": formControlsSection
            case "stateViews": stateViewsSection
            case "sectionHeader": sectionHeaderSection
            case "wave2": wave2Section
            case "wave3": wave3Section
            case "wave4": wave4Section
            case "wave5": wave5Section
            case "themeFoundation": themeFoundationSection
            default: EmptyView()
            }
        }
        .environment(\.ainkradTheme, tokens)
        .environment(\.ainkradStatusColors, statusColors)
        .environment(\.ainkradTypography, typography)
    }

    var foundationSection: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(
                title: "Foundation", subtitle: "Chamfer, brackets, accent rule, effects, status colors")

            HStack(spacing: AinkradSpacing.md) {
                ChamferShape()
                    .fill(galleryTokens.surfaceElevated)
                    .frame(width: 120, height: 80)
                    .cornerBrackets()
            }

            AccentRule(label: "Accent Rule")

            HStack(spacing: AinkradSpacing.md) {
                VStack(spacing: 4) {
                    effectSamplePanel.scanlineOverlay(active: scanlineOn)
                    AinkradCheckbox(isOn: $scanlineOn, label: "Scanline")
                        .font(AinkradFontResolver.font(.caption, typography: galleryTypography))
                        .foregroundStyle(galleryTokens.foreground.opacity(0.7))
                }

                VStack(spacing: 4) {
                    effectSamplePanel.hexGridBackground(active: hexGridOn)
                    AinkradCheckbox(isOn: $hexGridOn, label: "Hex Grid")
                        .font(AinkradFontResolver.font(.caption, typography: galleryTypography))
                        .foregroundStyle(galleryTokens.foreground.opacity(0.7))
                }

                VStack(spacing: 4) {
                    effectSamplePanel.glowBloom(active: glowBloomOn)
                    AinkradCheckbox(isOn: $glowBloomOn, label: "Glow Bloom")
                        .font(AinkradFontResolver.font(.caption, typography: galleryTypography))
                        .foregroundStyle(galleryTokens.foreground.opacity(0.7))
                }
            }

            HStack(spacing: AinkradSpacing.lg) {
                statusSwatch(label: "Success", color: galleryTheme.skin.color(\.success))
                statusSwatch(label: "Warning", color: galleryTheme.skin.color(\.warning))
                statusSwatch(label: "Danger", color: galleryTheme.skin.color(\.danger))
            }
            .padding(.top, AinkradSpacing.sm)
        }
    }

    private var effectSamplePanel: some View {
        RoundedRectangle(cornerRadius: AinkradRadius.sm)
            .fill(galleryTokens.surface)
            .frame(width: 96, height: 64)
    }

    private func statusSwatch(label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: AinkradRadius.sm)
                .fill(color)
                .frame(width: 64, height: 32)
            Text(label)
                .font(AinkradFontResolver.font(.caption, typography: galleryTypography))
                .foregroundStyle(galleryTokens.foreground.opacity(0.6))
        }
    }

    var scalesSection: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Scales", subtitle: "Spacing, radius, elevation, type roles")

            HStack(spacing: AinkradSpacing.sm) {
                ForEach(spacingSamples, id: \.label) { sample in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(galleryTokens.accentPrimary.opacity(0.6))
                            .frame(width: sample.value, height: 12)
                        Text(sample.label)
                            .font(AinkradFontResolver.font(.caption, typography: galleryTypography))
                            .foregroundStyle(galleryTokens.foreground.opacity(0.6))
                    }
                }
            }

            HStack(spacing: AinkradSpacing.md) {
                ForEach(radiusSamples, id: \.label) { sample in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: sample.value)
                            .fill(galleryTokens.surfaceElevated)
                            .frame(width: 48, height: 32)
                        Text(sample.label)
                            .font(AinkradFontResolver.font(.caption, typography: galleryTypography))
                            .foregroundStyle(galleryTokens.foreground.opacity(0.6))
                    }
                }
            }

            HStack(spacing: AinkradSpacing.lg) {
                elevationSample(label: "level0", shadow: AinkradElevation.level0)
                elevationSample(label: "level1", shadow: AinkradElevation.level1)
                elevationSample(label: "level2", shadow: AinkradElevation.level2)
            }
            .padding(.top, AinkradSpacing.sm)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(AinkradTypeRole.allCases, id: \.self) { role in
                    Text("\(String(describing: role)) — \(Int(role.size))pt")
                        .font(AinkradFontResolver.font(role, typography: galleryTypography))
                        .foregroundStyle(galleryTokens.foreground)
                }
            }
            .padding(.top, AinkradSpacing.sm)
        }
    }

    var panelSection: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Panel")
            AinkradPanel {
                Text("AinkradPanel content")
                    .font(AinkradFontResolver.font(.body, typography: galleryTypography))
                    .foregroundStyle(galleryTokens.foreground)
                    .padding(AinkradSpacing.lg)
            }
            .frame(height: 80)
        }
    }

    var cardSection: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Card", subtitle: "Default, hover-capable, selected")
            HStack(spacing: AinkradSpacing.md) {
                AinkradCard {
                    cardLabel("Default")
                }
                AinkradCard(onTap: {}) {
                    cardLabel("Interactive")
                }
                AinkradCard(isSelected: true) {
                    cardLabel("Selected")
                }
            }
        }
    }

    private func cardLabel(_ text: String) -> some View {
        Text(text)
            .font(AinkradFontResolver.font(.body, typography: galleryTypography))
            .foregroundStyle(galleryTokens.foreground)
            .frame(maxWidth: .infinity, minHeight: 44)
    }

    var pickersSection: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Pickers")
            AinkradSegmentedPicker(items: Array(0..<3), selection: $pickerSelection) { "Item \($0)" }
            AinkradSelect(items: ["Option A", "Option B", "Option C"], selection: $menuSelection) { $0 }
        }
    }

    var formControlsSection: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Form Controls")
            AinkradFormRow(title: "Enable feature", help: "A toggle in a form row") {
                AinkradToggle(isOn: $toggleOn)
            }
            AinkradTextField(text: $textFieldText, placeholder: "Text field")
            AinkradSecureField(text: $secureText, placeholder: "Secure field")
            AinkradSlider(value: $sliderValue, in: 0...1)
        }
    }

    var stateViewsSection: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "State Views")
            HStack(spacing: AinkradSpacing.md) {
                AinkradEmptyState(
                    icon: "tray", title: "Nothing here", message: "No items yet.",
                    actionTitle: "Add Item", action: {}
                )
                .frame(height: 180)
                AinkradLoadingState(label: "Loading…")
                    .frame(height: 180)
                AinkradErrorState(message: "Something went wrong.", retryTitle: "Retry", retry: {})
                    .frame(height: 180)
            }
        }
    }

    var sectionHeaderSection: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Section Header", subtitle: "Uppercased caption label, no separator line")
        }
    }


    private func elevationSample(label: String, shadow: ShadowSpec) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: AinkradRadius.sm)
                .fill(galleryTokens.surfaceElevated)
                .frame(width: 64, height: 40)
                .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
            Text(label)
                .font(AinkradFontResolver.font(.caption, typography: galleryTypography))
                .foregroundStyle(galleryTokens.foreground.opacity(0.6))
        }
    }

    private var spacingSamples: [(label: String, value: CGFloat)] {
        [
            ("xs", AinkradSpacing.xs), ("sm", AinkradSpacing.sm), ("md", AinkradSpacing.md),
            ("lg", AinkradSpacing.lg), ("xl", AinkradSpacing.xl), ("xxl", AinkradSpacing.xxl),
        ]
    }

    private var radiusSamples: [(label: String, value: CGFloat)] {
        [("sm", AinkradRadius.sm), ("md", AinkradRadius.md), ("lg", AinkradRadius.lg), ("panel", AinkradRadius.panel)]
    }
}
#endif
