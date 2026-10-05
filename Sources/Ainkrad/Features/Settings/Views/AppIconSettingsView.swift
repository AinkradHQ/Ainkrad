import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// Shared captions for the app-icon control, used by both the Settings pane
/// (this file) and the wizard's Appearance step (`SetupAppearanceStepView`).
/// The two used to hardcode their own copy and drifted — "Color"/"Colour" and
/// "Appearance"/"Light or dark" for the same two axes. "Color" is the
/// dominant spelling elsewhere in the app's user-facing strings, so it wins
/// here; same idiom as `UserProfileField.all` and `AccentSelection` being the
/// one place two sites agree on shared copy/logic.
enum AppIconCaptions {
    static let color = "Color"
    static let appearance = "Appearance"
}

/// Settings → App Icon: manual picker for the running app's Dock icon.
/// COLOR (Auto/Blue/Purple; Auto follows the theme) and APPEARANCE
/// (System/Light/Dark; Light/Dark pin one variant), with a live preview.
struct AppIconSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let tokens = environment.themeManager.tokens
        let store = environment.appIconStore
        return AinkradSettingsPanel(
            title: "App icon",
            hint: "The icon Ainkrad shows in the Dock."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose the Dock icon. Auto follows your theme; System follows the Dock's light/dark.")
                    .font(AinkradFont.display(11))
                    .foregroundStyle(tokens.foreground.opacity(0.5))

                preview(store: store, tokens: tokens)

                AinkradCaptionedRow(AppIconCaptions.color) {
                    AinkradSegmentedPicker(
                        items: AppIconChoice.allCases,
                        selection: Binding(get: { store.choice }, set: { store.selectColor($0) }),
                        label: colorTitle
                    )
                }
                AinkradCaptionedRow(AppIconCaptions.appearance) {
                    AinkradSegmentedPicker(
                        items: AppIconAppearance.allCases,
                        selection: Binding(get: { store.appearance }, set: { store.selectAppearance($0) }),
                        label: appearanceTitle
                    )
                }
            }
        }
    }

    // The resolved icon for the current selection (preview uses the current
    // system appearance for `.system`).
    private func preview(store: AppIconStore, tokens: DesignTokens) -> some View {
        let systemDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let name = AppIconResolver.resourceName(
            for: store.choice, theme: environment.themeManager.currentTheme,
            appearance: store.appearance, systemDark: systemDark)
        return HStack {
            Spacer()
            Group {
                if let url = Bundle.main.url(forResource: name, withExtension: "icns"),
                    let img = NSImage(contentsOf: url)
                {
                    Image(nsImage: img).resizable().scaledToFit()
                } else {
                    ChamferShape(cut: 20).fill(tokens.surfaceElevated)
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(ChamferShape(cut: 22))
            Spacer()
        }
    }

    private func colorTitle(_ c: AppIconChoice) -> String {
        switch c {
        case .auto: return "Auto"
        case .blue: return "Blue"
        case .purple: return "Purple"
        }
    }
    private func appearanceTitle(_ a: AppIconAppearance) -> String {
        switch a {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}
