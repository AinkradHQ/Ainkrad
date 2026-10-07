import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// Renders the current `DevHostModel.State`. `.loaded` renders the plugin's
/// own root view via its `makeRootView` factory, honoring the bundle's
/// declared presentation; `.empty`/`.invalid` render a minimal placeholder.
/// The log pane + validation banner are separate views composed alongside
/// this one in `DevHostApp` — see `ValidationBanner`, `LogPaneView`.
struct PluginStageView: View {
    let state: DevHostModel.State
    var surface: DevHostModel.Surface = .root

    @Environment(\.ainkradSkin) private var skin

    /// Picks the plugin's view factory for `surface`.
    ///
    /// Settings render the app's declared `settingsCatalog` through the kit,
    /// as the real host's Settings does; plugins' legacy settings views go
    /// away in 5B/5C (decision 14). An app that publishes no catalog yet
    /// falls back to `makeSettingsView`, the real host's fallback too.
    ///
    /// Static and separate from `body` because that is the only seam a test
    /// can observe: `AnyView` cannot be inspected, so a test proves the
    /// right surface by which FACTORY was invoked, not by what came back.
    @MainActor
    static func view(for app: RegisteredApp, surface: DevHostModel.Surface) -> AnyView {
        switch surface {
        case .root: return app.makeRootView()
        case .settings:
            guard let page = app.settingsCatalog() else { return app.makeSettingsView() }
            return AnyView(
                AinkradSettingsPanel(title: page.title) {
                    SettingsPageView(page: page)
                })
        }
    }

    var body: some View {
        switch state {
        case .empty:
            placeholder("No bundle loaded", systemImage: "app.dashed")
        case .invalid(let message):
            placeholder(message, systemImage: "exclamationmark.triangle")
        case .loaded(let app):
            // The presentation styling describes the plugin's ROOT surface;
            // settings render plainly, as they do in the real host's
            // settings window rather than in an overlay.
            switch (surface, app.presentation) {
            case (.settings, _):
                Self.view(for: app, surface: .settings)
            case (.root, .overlay):
                Self.view(for: app, surface: .root)
                    .background(.regularMaterial)
            default:
                Self.view(for: app, surface: .root)
            }
        }
    }

    private func placeholder(_ message: String, systemImage: String) -> some View {
        VStack(spacing: skin.spacing.sm) {
            Image(systemName: systemImage)
                .font(.largeTitle)
            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
