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
    @Environment(\.ainkradSkin) private var skin

    /// The kit banner states the problem; the route back sits beside it,
    /// because `AinkradBanner` carries a message and an optional dismiss but no
    /// action of its own.
    var body: some View {
        HStack(spacing: skin.spacing.sm) {
            AinkradBanner(message: "AI features are off — no provider is connected yet.", status: .warning)

            AinkradButton(title: "Connect a provider", style: .secondary) {
                // Re-raising the gate is the whole route back: the coordinator
                // is rebuilt from the marker, which still owes `.providers`.
                environment.isSetupPresented = true
            }
            .accessibilityIdentifier("workspace.providersDeferred.resume")
        }
        .padding(.horizontal, skin.spacing.lg)
        .padding(.bottom, skin.spacing.sm)
        .accessibilityIdentifier("workspace.providersDeferred.banner")
    }
}
