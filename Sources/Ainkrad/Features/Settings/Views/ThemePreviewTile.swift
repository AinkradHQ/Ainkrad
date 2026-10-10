import AinkradAppKit
import SwiftUI

/// A live miniature of one theme or colour scheme: a kit panel on the skin's own
/// backdrop, with a title bar, two accent bars and two text lines. A real
/// SwiftUI subtree under `.ainkradSkin(previewSkin)` — never an `ImageRenderer`
/// image, which cannot draw AppKit views — so the panel's material, shape and
/// glow are the language's own.
///
/// A glass panel inside an opaque window has nothing behind it to sample, so a
/// glass skin gets a gradient of its own colours behind the panel.
struct ThemePreviewTile: View {
    let previewSkin: AinkradSkin
    let width: CGFloat

    var body: some View {
        let s = previewSkin
        let height = width * 0.62
        let line = max(2, width / 40)
        ZStack {
            if s.material.kind == "glass" {
                LinearGradient(
                    colors: [s.color(\.accentSecondary), s.color(\.surfaceElevated), s.color(\.background)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                s.color(\.background)
            }
            VStack(alignment: .leading, spacing: line * 1.5) {
                HStack(spacing: line) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(s.color(\.foreground).opacity(s.opacity.o25)).frame(width: line * 1.5)
                    }
                }
                Capsule().fill(s.color(\.accentPrimary)).frame(width: width * 0.42, height: line)
                Capsule().fill(s.color(\.accentSecondary)).frame(width: width * 0.28, height: line)
                Capsule().fill(s.color(\.foreground).opacity(s.opacity.o35)).frame(width: width * 0.5, height: line)
                Capsule().fill(s.color(\.foreground).opacity(s.opacity.o18)).frame(width: width * 0.36, height: line)
            }
            .padding(line * 2.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ainkradPanel()
            .padding(width / 12)
        }
        .frame(width: width, height: height)
        .clipShape(s.shape(cut: s.cut.c7))
        .ainkradSkin(s)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The theme picker as preview cards, shared by Setup's Appearance step and
/// Settings → Appearance: one card per installed theme, or one per colour scheme
/// of the current appearance on the current theme. Picks go through `ThemeManager`.
struct ThemeChoiceGrid: View {
    enum Choice { case themes, schemes }
    let choice: Choice

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let manager = environment.themeManager
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: skin.size.s200, maximum: skin.size.s260), spacing: skin.size.s10)],
            spacing: skin.size.s10
        ) {
            switch choice {
            case .themes:
                ForEach(manager.themes, id: \.id) { theme in
                    card(
                        theme.name, isSelected: manager.activeThemeID == theme.id,
                        swatch: manager.previewSkin(forTheme: theme.id) ?? manager.skin
                    ) { manager.setTheme(theme.id) }
                }
            case .schemes:
                ForEach(manager.colorSchemes, id: \.id) { scheme in
                    card(
                        scheme.name, isSelected: manager.skin.id == scheme.id,
                        swatch: manager.skin(forScheme: scheme.id) ?? manager.skin
                    ) { manager.setColorScheme(scheme.id, for: manager.appearance) }
                }
            }
        }
    }

    /// A kit list row: a live preview of the swatch skin as the leading chip,
    /// and a tick that reads as the current choice.
    private func card(
        _ title: String, isSelected: Bool, swatch: AinkradSkin, onTap: @escaping () -> Void
    ) -> some View {
        let tokens = environment.themeManager.hostSkin
        return AinkradListRow(
            isSelected: isSelected,
            onTap: onTap,
            leading: { ThemePreviewTile(previewSkin: swatch, width: skin.size.s56) },
            title: title,
            trailing: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(skin.font(AinkradFontToken(sizeKey: "t13", scaled: false)))
                    .foregroundStyle(
                        isSelected ? tokens.color(\.accentSecondary) : tokens.color(\.foreground).opacity(skin.opacity.o25))
            }
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
