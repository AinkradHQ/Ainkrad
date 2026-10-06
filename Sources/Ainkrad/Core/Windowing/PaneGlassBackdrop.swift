import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// The host-rendered Gaussian blur revealed through a translucent pane.
///
/// A view can't blur the layers behind it, so the host draws its own sky+island
/// copy here and blurs that. It sits behind the whole pane, so everything in it
/// frosts continuously (no seam).
///
/// ## Why this is its own view and not a `.background { }` closure
///
/// It used to be inlined in `BlockView.body`, which meant every focus change
/// re-evaluated it — and re-rasterized its `drawingGroup`. Measured, a single
/// tab switch rebuilt this backdrop five times and stalled the main thread for
/// up to 184ms (~11 dropped frames), while an idle app drifted 0.9ms. The blur
/// does not depend on focus at all, so as a separate view with one `Bool` input
/// SwiftUI compares that input, sees it unchanged, and skips the whole subtree.
///
/// ## Why one shared image and not a `drawingGroup`
///
/// A `drawingGroup` keeps a pane-sized, full-resolution texture per pane — in
/// Focus Mode every tab is canvas-sized, so five panes held ~263 MB of
/// half-float textures of the same blurred picture. At radius 26 nothing
/// finer than a few points survives the blur, so ONE copy is rendered at half
/// scale for a fixed canvas and every pane shows it aspect-filled. Size is not
/// an input: adding a pane, dragging a divider or entering full screen renders
/// nothing (rendering per size stalled the main thread on every one of those).
struct PaneGlassBackdrop: View {
    let isEnabled: Bool
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        if isEnabled {
            let key = PaneGlassImageCache.Key(
                theme: environment.themeManager.currentTheme.rawValue,
                tokens: environment.themeManager.hostSkin,
                effects: environment.skySettingsStore.effectEnabled)
            GeometryReader { proxy in
                if let image = PaneGlassImageCache.image(for: key, render: render) {
                    Image(decorative: image, scale: PaneGlassImageCache.scale)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
            }
        }
    }

    private func render() -> CGImage? {
        let renderer = ImageRenderer(
            content:
                backdrop
                .frame(width: PaneGlassImageCache.canvas.width, height: PaneGlassImageCache.canvas.height)
                .environment(environment))
        renderer.scale = PaneGlassImageCache.scale
        return renderer.cgImage
    }

    private var backdrop: some View {
        ZStack {
            // `isLive: false` — this copy exists only to be blurred at
            // radius 26, where 30fps starfield drift is not perceptible.
            // The real sky behind the workspace still animates; nothing the
            // user can actually see stopped moving.
            AmbientSkyView(isLive: false)
            FloatingIslandView()
                .frame(maxWidth: skin.size.s860, maxHeight: skin.size.s574)
        }
        .blur(radius: skin.size.s26)
    }
}

/// The one backdrop every pane shows, and what it was rendered for. Not
/// observed: holding the render must not itself re-render anything.
@MainActor
enum PaneGlassImageCache {
    static let scale: CGFloat = 0.5
    /// A typical full-screen canvas; panes of any size aspect-fill from it.
    static let canvas = CGSize(width: 1712, height: 1008)

    struct Key: Equatable {
        let theme: String
        let tokens: AinkradSkin
        let effects: [String: Bool]
    }

    private static var key: Key?
    private static var image: CGImage?

    static func image(for key: Key, render: () -> CGImage?) -> CGImage? {
        if key != self.key {
            self.key = key
            image = render()
        }
        return image
    }
}
