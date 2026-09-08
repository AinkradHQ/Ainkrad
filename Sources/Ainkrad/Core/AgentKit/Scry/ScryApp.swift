import SwiftUI
import AinkradAppKit

/// The compiled-in Live Scry app — a tiled surface of agent-rendered layered
/// cards. Host-embedded (reads `AppEnvironment` directly like `SageApp`);
/// `host` satisfies the registration contract only.
enum ScryApp: AinkradApp {
    static let id = "scry"
    static let displayName = "Scry"
    static let icon = "square.on.square"

    static func makeRootView(host: HostServices) -> AnyView { AnyView(ScryHostView()) }
    static func makeSettingsView(host: HostServices) -> AnyView { AnyView(EmptyView()) }
}

/// Thin wrapper so the pane can pull `scryStore` from the environment.
@MainActor
private struct ScryHostView: View {
    @Environment(AppEnvironment.self) private var environment
    var body: some View { ScryView(store: environment.scryStore) }
}
