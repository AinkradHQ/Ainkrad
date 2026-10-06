import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// The in-app HUD shown before Ainkrad actually quits — summoned by
/// `QuitCoordinator.isConfirming` from ⌘Q, the app menu's Quit, or the
/// Dock's Quit (all funnel through `AinkradAppDelegate.applicationShouldTerminate`).
/// Same visual language as the Launcher/Settings/App Store/Workspace
/// Overview overlays. Cancel keeps the app running; Quit (optionally with
/// "Don't ask again") delivers the coordinator's deferred termination reply.
///
/// Not `AinkradConfirmDialog`: the kit dialog has no accessory control for
/// the "Don't ask again" checkbox and no Return/Escape shortcuts — a kit gap
/// ("confirm dialog with an accessory checkbox"). Local, on skin tokens and
/// the kit's overlay chrome.
struct QuitConfirmationView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradSkin) private var skin
    @State private var dontAskAgain = false

    var body: some View {
        let tokens = environment.themeManager.hostSkin
        let coordinator = environment.quitCoordinator

        GeometryReader { geo in
            ZStack {
                skin.color(.palette("black", skin.chrome.overlay.backdropOpacity))
                    .ignoresSafeArea()
                    .onTapGesture { coordinator.cancel() }

                panel(tokens: tokens, coordinator: coordinator)
                    .frame(width: min(max(340, geo.size.width * 0.3), 420))
            }
        }
    }

    private func panel(tokens: AinkradSkin, coordinator: QuitCoordinator) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: skin.spacing.sm) {
                Text("Quit Ainkrad?")
                    .font(AinkradFont.display(16, weight: .semibold))
                    .foregroundStyle(tokens.color(\.foreground))

                Text("Running workspaces and their sessions will end.")
                    .font(AinkradFont.display(12))
                    .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o62))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, skin.size.s26)
            .padding(.horizontal, skin.size.s26)
            .padding(.bottom, skin.size.s18)

            AinkradCheckbox(isOn: $dontAskAgain, label: "Don't ask again")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, skin.size.s26)
                .padding(.bottom, skin.size.s20)

            HStack(spacing: skin.spacing.sm) {
                Spacer(minLength: 0)
                AinkradButton(title: "Cancel", style: .ghost) { coordinator.cancel() }
                    .keyboardShortcut(.cancelAction)
                AinkradButton(title: "Quit", style: .danger) {
                    environment.sounds.play(.appQuit)
                    coordinator.confirm(dontAskAgain: dontAskAgain)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(skin.size.s20)
        }
        // The user's overlay opacity and blur settings, as every summoned
        // overlay reads them.
        .ainkradOverlayChrome(
            backgroundOpacity: environment.generalSettingsStore.overlayBackgroundOpacity,
            blurEnabled: environment.generalSettingsStore.overlayBlurEnabled,
            blending: .withinWindow
        )
        .onKeyPress(.escape) {
            coordinator.cancel()
            return .handled
        }
    }
}
