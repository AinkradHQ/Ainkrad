import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// Slice 3's floating host overlay for `.overlay`-presentation plugin apps —
/// summoned from the Launcher instead of tiling into the workspace layout.
/// Mirrors `LauncherView`'s scrim + kit overlay-chrome panel composition, but
/// hosts a `RegisteredApp`'s own root view rather than the app-picker UI.
struct PluginOverlayView: View {
    let app: RegisteredApp
    /// The mode this overlay opens in — the app's resolved default. An overlay
    /// is one transient surface rather than a managed pane, so there is no
    /// `Block` to hold a switched mode; a switch lives in `selection` for this
    /// open only, and the next open starts from the default again.
    ///
    /// Declared BEFORE `onDismiss` so the memberwise initializer keeps that
    /// closure last and the trailing-closure call site still reads naturally.
    var mode: PluginMode = .advanced
    /// How large to draw it. Fractions of the window with clamps, so the same
    /// choice reads the same on a laptop and a 32" display.
    var size: PluginOverlaySize = .default
    let onDismiss: () -> Void

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradSkin) private var skin
    @FocusState private var isFocused: Bool
    @State private var selection = OverlayModeSelection()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                skin.color(.palette("black", skin.chrome.overlay.backdropOpacity))
                    .ignoresSafeArea()
                    .onTapGesture { onDismiss() }

                app.makeRootView(mode: selection.resolved(default: mode))
                    .frame(
                        width: size.resolved(in: geo.size).width,
                        height: size.resolved(in: geo.size).height
                    )
                    .ainkradOverlayChrome(
                        backgroundOpacity: environment.generalSettingsStore.overlayBackgroundOpacity,
                        blurEnabled: environment.generalSettingsStore.overlayBlurEnabled,
                        blending: .withinWindow
                    )
                    // Same pair `WorkspacePaneLayer` injects per pane: without it
                    // the app's `AinkradModeSwitch` reads the environment default
                    // (.advanced, no-op) while the root is built in basic.
                    .environment(\.ainkradPaneMode, selection.resolved(default: mode))
                    .environment(\.ainkradSetPaneMode) { selection.switched = $0 }
                    .focusable()
                    .focused($isFocused)
                    .focusEffectDisabled()
                    .onKeyPress(.escape) {
                        onDismiss()
                        return .handled
                    }
                    .offset(y: -28)
            }
        }
        .onAppear { isFocused = true }
    }
}

/// The overlay's switched mode. `nil` follows the app's resolved default, so a
/// setting change still moves an overlay that was never switched — the same
/// rule as `Block.mode` for panes. Pure value so the rule is testable.
struct OverlayModeSelection: Equatable {
    var switched: PluginMode?

    func resolved(default fallback: PluginMode) -> PluginMode { switched ?? fallback }
}
