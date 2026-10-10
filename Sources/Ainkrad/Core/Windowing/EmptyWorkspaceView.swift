import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// The empty workspace: the ambient sky shows through, with the floating
/// island artwork, wordmark, and a HUD-style Launcher prompt at center.
/// A theme without the island art (`islandArt: false`) shows the brand mark,
/// wordmark and Launcher hint instead. See Navigation & Settings Architecture.md.
struct EmptyWorkspaceView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradSkin) private var skin

    /// Whether this workspace is the one currently on screen. Non-active
    /// workspaces (e.g. rendered off-canvas or behind an overlay) still
    /// exist in the view tree, so the island's motion must be gated off
    /// them to avoid burning cycles on artwork nobody sees.
    var isActiveWorkspace: Bool = true

    /// True when a full-screen overlay is covering the island — the
    /// Launcher, Workspace Overview, Settings, App Store, or the quit
    /// confirmation. Motion pauses under any of these too.
    private var overlayPresented: Bool {
        environment.isLauncherPresented
            || environment.isWorkspaceOverviewPresented
            || environment.isSettingsPresented
            || environment.isAppStorePresented
            || environment.quitCoordinator.isConfirming
    }

    private var islandVisible: Bool {
        isActiveWorkspace && !overlayPresented
    }

    var body: some View {
        switch environment.themeManager.homeLanguage.island {
        case .art:
            // The artwork carries the wordmark and tagline itself — no native
            // text or shortcut hint over it; the empty workspace is just the
            // hero over the live sky.
            FloatingIslandView(isVisible: islandVisible)
                .frame(maxWidth: skin.size.s860, maxHeight: skin.size.s574)
        case .glass:
            GlassIslandView(isVisible: islandVisible)
                .frame(maxWidth: skin.size.s860, maxHeight: skin.size.s574)
        case .mark:
            brandHome
        }
    }

    /// The calm home for a theme without the island art: the brand mark and
    /// wordmark, and the one shortcut that does something from here.
    private var brandHome: some View {
        let tokens = environment.themeManager.hostSkin
        let launcher = environment.shortcutStore.chord(for: .openLauncher).displayString
        return VStack(spacing: skin.spacing.lg) {
            AinkradBrandChevron()
                .fill(tokens.color(\.accentSecondary))
                .frame(width: skin.size.s54, height: skin.size.s46)
            Text("AINKRAD")
                .font(AinkradFont.display(16, weight: .semibold))
                .kerning(6)
                .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o90))
            HStack(spacing: skin.spacing.sm) {
                AinkradKbd(launcher)
                Text("to open an app")
                    .font(AinkradFont.display(12))
                    .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o45))
            }
            .padding(.top, skin.spacing.xl)
        }
        .accessibilityElement(children: .combine)
    }
}
