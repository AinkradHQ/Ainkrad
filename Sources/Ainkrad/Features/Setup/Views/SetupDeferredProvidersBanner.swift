import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// The honest half of "Set this up later".
///
/// A user who deferred the Providers step is in a workspace where the assistant
/// cannot work at all. A silently half-configured app is worse than the block
/// this replaced, so the state is stated plainly and permanently — this banner
/// has no dismiss control on purpose — and it carries the route back: the button
/// re-raises the first-run gate, which (the marker still owing `.providers`)
/// resolves to that step alone, not a replay of the wizard.
///
/// It sits inside the workspace stack rather than over it: it is workspace
/// content, so it blurs with everything else when an overlay is raised, and it
/// never covers the setup gate it summons.
struct SetupDeferredProvidersBanner: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let tokens = environment.themeManager.tokens

        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(tokens.accentTertiary)

            Text("AI features are off — no provider is connected yet.")
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            AinkradButton(title: "Connect a provider", style: .secondary) {
                // Re-raising the gate is the whole route back: the coordinator
                // is rebuilt from the marker, which still owes `.providers`.
                environment.isSetupPresented = true
            }
            .accessibilityIdentifier("workspace.providersDeferred.resume")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.surfaceElevated.opacity(0.55)))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityIdentifier("workspace.providersDeferred.banner")
    }
}
