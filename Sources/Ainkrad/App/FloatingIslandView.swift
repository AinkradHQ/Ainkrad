import AinkradHostRuntime
import AppKit
import SwiftUI

/// The floating-island hero artwork at the center of an empty workspace
/// (AIN-107, "Living Island"). Renders the static painted artwork for the
/// active theme.
///
/// Each colour scheme can ship its own painting as an asset named `Island-<Scheme>`
/// (PascalCase of the composed skin's id = the scheme id, e.g. `Island-Nord`, matching the
/// existing `Island-NeonBlue` / `Island-CyberPurple`). When a theme has no
/// dedicated painting yet, it falls back to whichever of the two originals is
/// closest in spirit — so adding a themed illustration to the asset catalog is
/// all that's needed to light it up here, no code change.
///
/// Live motion (depth-parallax, ambient sway/breathe/glow, drifting
/// particles, a reactive energy ring/flare) was previously layered on here
/// and has been removed — the plain static image is the intended baseline.
/// `isVisible` is kept as the gating hook for any future motion work; the
/// static image ignores it.
struct FloatingIslandView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Whether the island is the one currently on screen. Unused while the
    /// artwork is static; retained so a future live version can gate its
    /// motion off backgrounded or covered workspaces without a signature
    /// change here or at the call site (`EmptyWorkspaceView.islandVisible`).
    var isVisible: Bool = true

    private var imageName: String {
        let scheme = environment.themeManager.skin.id
        // A dedicated painting for this scheme wins if it's in the catalog.
        let dedicated = "Island-" + scheme.prefix(1).uppercased() + scheme.dropFirst()
        if NSImage(named: dedicated) != nil { return dedicated }
        // Otherwise fall back to the nearest of the two shipped originals.
        switch scheme {
        case "cyberPurple", "dracula", "tokyoNight": return "Island-CyberPurple"
        default: return "Island-NeonBlue"
        }
    }

    var body: some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
    }
}
