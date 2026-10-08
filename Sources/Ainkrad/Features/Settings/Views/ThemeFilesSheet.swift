import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// Settings → Appearance → Theme files: the theme and colour-scheme files
/// that could not load, one per line. Presented in the kit's `ainkradModal`.
struct ThemeFilesSheet: View {
    let issues: [String]
    let onClose: () -> Void

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradStatusColors) private var statusColors
    @Environment(\.ainkradSkin) private var skin

    private var tokens: AinkradSkin { environment.themeManager.hostSkin }

    var body: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.lg) {
            Text(issues.isEmpty ? "Every theme file loaded" : "Theme files that could not load")
                .font(AinkradFontResolver.font(.headline, weight: .medium, typography: typo))
                .foregroundStyle(tokens.color(\.foreground))

            if !issues.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AinkradSpacing.sm) {
                        ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                            HStack(alignment: .firstTextBaseline, spacing: AinkradSpacing.sm) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(statusColors.warning)
                                Text(issue)
                                    .font(AinkradFontResolver.font(.caption, typography: typo))
                                    .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o85))
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(AinkradSpacing.sm)
                }
                .frame(height: skin.size.s200)
                .background(skin.shape(cut: skin.cut.c6).fill(tokens.color(\.foreground).opacity(skin.opacity.o05)))
            }

            HStack {
                Spacer()
                AinkradButton(title: "Done", style: .primary, action: onClose)
            }
        }
    }
}
