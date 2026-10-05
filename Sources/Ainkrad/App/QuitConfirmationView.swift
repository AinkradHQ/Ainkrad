import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// The in-app HUD shown before Ainkrad actually quits — summoned by
/// `QuitCoordinator.isConfirming` from ⌘Q, the app menu's Quit, or the
/// Dock's Quit (all funnel through `AinkradAppDelegate.applicationShouldTerminate`).
/// Same visual language as the Launcher/Settings/App Store/Workspace
/// Overview overlays. Cancel keeps the app running; Quit (optionally with
/// "Don't ask again") delivers the coordinator's deferred termination reply.
struct QuitConfirmationView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var dontAskAgain = false

    var body: some View {
        let tokens = environment.themeManager.tokens
        let coordinator = environment.quitCoordinator

        GeometryReader { geo in
            ZStack {
                Color.black.opacity(OverlayChrome.backdropOpacity)
                    .ignoresSafeArea()
                    .onTapGesture { coordinator.cancel() }

                panel(tokens: tokens, coordinator: coordinator)
                    .frame(width: min(max(340, geo.size.width * 0.3), 420))
            }
        }
    }

    private func panel(tokens: DesignTokens, coordinator: QuitCoordinator) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Quit Ainkrad?")
                    .font(AinkradFont.display(16, weight: .semibold))
                    .foregroundStyle(tokens.foreground)

                Text("Running workspaces and their sessions will end.")
                    .font(AinkradFont.display(12))
                    .foregroundStyle(tokens.foreground.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 26)
            .padding(.horizontal, 26)
            .padding(.bottom, 18)

            AinkradCheckbox(isOn: $dontAskAgain, label: "Don't ask again")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 26)
                .padding(.bottom, 20)

            HStack(spacing: AinkradSpacing.sm) {
                Spacer(minLength: 0)
                AinkradButton(title: "Cancel", style: .ghost) { coordinator.cancel() }
                    .keyboardShortcut(.cancelAction)
                AinkradButton(title: "Quit", style: .danger) {
                    environment.sounds.play(.appQuit)
                    coordinator.confirm(dontAskAgain: dontAskAgain)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .hudPanelChrome(tokens: tokens)
        .onKeyPress(.escape) {
            coordinator.cancel()
            return .handled
        }
    }
}
