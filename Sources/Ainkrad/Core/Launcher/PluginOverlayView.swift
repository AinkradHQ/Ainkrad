import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Slice 3's floating host overlay for `.overlay`-presentation plugin apps —
/// summoned from the Launcher instead of tiling into the workspace layout.
/// Mirrors `LauncherView`'s scrim + `hudPanelChrome` panel composition, but
/// hosts a `RegisteredApp`'s own root view rather than the app-picker UI.
struct PluginOverlayView: View {
    let app: RegisteredApp
    let tokens: DesignTokens
    /// The mode this overlay opens in — the app's resolved default. An overlay
    /// is one transient surface rather than a managed pane, so there is no
    /// `Block` to hold a switched mode; it opens in the default every time.
    ///
    /// Declared BEFORE `onDismiss` so the memberwise initializer keeps that
    /// closure last and the trailing-closure call site still reads naturally.
    var mode: PluginMode = .advanced
    /// How large to draw it. Fractions of the window with clamps, so the same
    /// choice reads the same on a laptop and a 32" display.
    var size: PluginOverlaySize = .default
    let onDismiss: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(OverlayChrome.backdropOpacity)
                    .ignoresSafeArea()
                    .onTapGesture { onDismiss() }

                app.makeRootView(mode: mode)
                    .frame(width: min(max(size.width.min, geo.size.width * size.width.fraction),
                                      size.width.max),
                           height: min(max(size.height.min, geo.size.height * size.height.fraction),
                                       size.height.max))
                    .hudPanelChrome(tokens: tokens)
                    .focusable()
                    .focused($isFocused)
                    .focusEffectDisabled()
                    .onKeyPress(.escape) { onDismiss(); return .handled }
                    .offset(y: -28)
            }
        }
        .onAppear { isFocused = true }
    }
}
