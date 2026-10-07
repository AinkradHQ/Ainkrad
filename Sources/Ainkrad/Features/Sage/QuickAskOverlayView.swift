import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// A summonable HUD overlay hosting the Sage surface (bound to the shared
/// `AgentSession`) so the user can ask from anywhere: streaming, gated tools,
/// and inline approvals all work because it IS the Sage surface, just in
/// an overlay frame. Its own new-chat header is suppressed (this view supplies
/// the bar) and its composer auto-focuses on appear. `Esc` dismisses; the
/// in-flight request keeps running in the shared session.
struct QuickAskOverlayView: View {
    @Environment(\.ainkradSkin) private var skin
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradTheme) private var theme
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            bar()
            SageRootView(showsHeader: false, autoFocusComposer: true)
        }
        .frame(width: skin.size.s640)
        .frame(maxHeight: skin.size.s560)
        .hudPanelChrome(tokens: environment.themeManager.hostSkin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, skin.size.s120)
        .onExitCommand { onDismiss() }
    }

    private func bar() -> some View {
        HStack(spacing: skin.size.s10) {
            Image(systemName: "sparkles")
                .font(skin.font(AinkradFontToken(sizeKey: "t12", scaled: false)))
                .foregroundStyle(theme.accentSecondary)
            Text("QUICK ASK")
                .font(AinkradFont.display(12, weight: .medium))
                .kerning(0.6)
                .foregroundStyle(theme.foreground.opacity(skin.opacity.o70))

            Spacer()

            AinkradButton(title: "Open in Sage", style: .ghost, icon: "arrow.up.forward.app") {
                // Same session, so "open" just reveals the thread in a pane.
                environment.workspaceManager.activeWorkspace.tileLayout.openApp(SageApp.id)
                onDismiss()
            }
            .help("Open this conversation in the Sage pane")
        }
        .padding(.horizontal, skin.spacing.lg)
        .frame(height: skin.size.s40)
    }
}
