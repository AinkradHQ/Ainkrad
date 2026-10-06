import SwiftUI

/// Blurs everything behind an overlay — the sky, the HUD bar and every mounted
/// workspace — and animates that blur in ONE direction only.
///
/// A SwiftUI `.blur` over the whole window has to rasterize the entire live
/// composition (animated sky, live terminals, every mounted workspace) and
/// Gaussian-blur it. That is the expensive part of raising an overlay, and the
/// two directions are not symmetric, which is the whole point of this type:
///
/// - **Blurring in** is expensive at full radius. Animating it ramps 0 → 14, so
///   the early frames blur at small (cheap) radii and the cost is spread across
///   the transition. Snapping straight to 14 does less total work but pays it
///   all in ONE frame, and one big stall is what a user sees as a glitch.
///   Measured A/B in a single build, back to back: animated 22.1ms median /
///   48.5ms p90, snapped 32.0 / 74.6. Animating wins.
/// - **Blurring out** has nothing to compute at radius 0. Animating it walks
///   back down through every expensive intermediate radius for no visual gain
///   whatsoever — the overlay on top is already fading away. Snapping: 10.8ms
///   median / 22.1ms p90 → 3.5 / 11.6.
///
/// So: ease in, snap out. Both numbers are against a 0.9ms idle floor.
struct OverlayBackdrop<Content: View>: View {
    /// The radius, tuned so overlay text reads cleanly over a busy sky.
    private static var radius: CGFloat { 14 }

    let isBlurred: Bool
    @ViewBuilder var content: Content

    var body: some View {
        content
            .blur(radius: isBlurred ? Self.radius : 0)
            // `RootView` wraps this whole stack in an `.easeOut(0.16)` keyed on
            // the same flag; this overrides it per direction, and the `nil` on
            // the way out is what stops the blur inheriting it.
            .animation(isBlurred ? .easeOut(duration: 0.16) : nil, value: isBlurred)
    }
}
