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
    @Environment(AppEnvironment.self) private var environment
    let onDismiss: () -> Void

    var body: some View {
        let tokens = environment.themeManager.tokens

        VStack(spacing: 0) {
            bar(tokens: tokens)
            SageRootView(showsHeader: false, autoFocusComposer: true)
        }
        .frame(width: 640)
        .frame(maxHeight: 560)
        .hudPanelChrome(tokens: tokens)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 120)
        .onExitCommand { onDismiss() }
    }

    private func bar(tokens: DesignTokens) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 12))
                .foregroundStyle(tokens.accentSecondary)
            Text("QUICK ASK")
                .font(AinkradFont.display(12, weight: .medium))
                .kerning(0.6)
                .foregroundStyle(tokens.foreground.opacity(0.7))

            Spacer()

            AinkradButton(title: "Open in Sage", style: .ghost, icon: "arrow.up.forward.app") {
                // Same session, so "open" just reveals the thread in a pane.
                environment.workspaceManager.activeWorkspace.tileLayout.openApp(SageApp.id)
                onDismiss()
            }
            .help("Open this conversation in the Sage pane")
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
    }
}
