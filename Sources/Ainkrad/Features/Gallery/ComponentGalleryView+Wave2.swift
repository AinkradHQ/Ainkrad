#if DEBUG
// design-lint: allow-file spacing-literal,radius-literal,opacity-literal,frame-literal gallery-sample — sample content, not chrome
import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Wave 2: surfaces, buttons, tags, type.
extension ComponentGalleryView {
    var wave2Section: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Surfaces · Buttons · Type", subtitle: "Wave-2 Cardinal HUD components")

            wave2SurfacesRow
            wave2SectionFrameSample
            wave2ButtonsRow
            wave2TagsRow
            wave2TypeRow
        }
    }

    private var wave2SurfacesRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Panel (default / bracketed) & Card (default / interactive / selected)")
            HStack(alignment: .top, spacing: AinkradSpacing.md) {
                AinkradPanel {
                    wave2SampleText("Panel")
                        .padding(AinkradSpacing.lg)
                }
                .frame(width: 140, height: 80)

                AinkradPanel(showsBrackets: true) {
                    wave2SampleText("Panel + brackets")
                        .padding(AinkradSpacing.lg)
                }
                .frame(width: 140, height: 80)

                AinkradCard {
                    wave2SampleText("Default")
                }
                AinkradCard(onTap: {}) {
                    wave2SampleText("Hover-capable")
                }
                AinkradCard(isSelected: true) {
                    wave2SampleText("Selected")
                }
            }
        }
    }

    private func wave2SampleText(_ text: String) -> some View {
        Text(text)
            .font(AinkradFontResolver.font(.body, typography: galleryTypography))
            .foregroundStyle(galleryTokens.foreground)
            .frame(maxWidth: .infinity, minHeight: 44)
    }

    private var wave2SectionFrameSample: some View {
        AinkradSectionFrame(title: "Section Frame") {
            AinkradLabel("Framed content sample", systemName: "square.stack.3d.up")
        }
    }

    private var wave2ButtonsRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Buttons — all 4 styles, icon button, toggle button")
            HStack(spacing: AinkradSpacing.md) {
                AinkradButton(title: "Primary", style: .primary, action: {})
                AinkradButton(title: "Secondary", style: .secondary, action: {})
                AinkradButton(title: "Ghost", style: .ghost, action: {})
                AinkradButton(title: "Danger", style: .danger, action: {})
                AinkradIconButton(systemName: "bolt.fill", action: {})
                AinkradToggleButton(isOn: $wave2ToggleOn, systemName: "power", title: "Latch")
            }
        }
    }

    private var wave2TagsRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Chips, badges (all statuses), keyboard shortcuts")
            HStack(spacing: AinkradSpacing.md) {
                ForEach(wave2Chips, id: \.self) { chip in
                    AinkradChip(
                        label: chip, systemName: "tag",
                        onRemove: {
                            wave2Chips.removeAll { $0 == chip }
                        })
                }
                AinkradChip(label: "Static")
            }
            HStack(spacing: AinkradSpacing.sm) {
                ForEach(AinkradStatus.allCases, id: \.self) { status in
                    AinkradBadge(text: String(describing: status), status: status)
                }
            }
            HStack(spacing: AinkradSpacing.xs) {
                AinkradKbd("⌘")
                AinkradKbd("⇧")
                AinkradKbd("K")
            }
        }
    }

    private var wave2TypeRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Label & Caption")
            AinkradLabel("Sample label text", systemName: "text.alignleft")
            AinkradCaption("Sample dimmed caption text")
        }
    }
}
#endif
