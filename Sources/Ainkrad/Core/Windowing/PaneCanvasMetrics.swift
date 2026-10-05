import AinkradAppKit
import CoreGraphics

/// Where a workspace's pane canvas sits inside the workspace's own frame.
///
/// This exists because the panes and the chrome around them are no longer drawn
/// by the same view. Panes render in ONE flat layer spanning every workspace
/// (see `WorkspacePaneLayer`, and the rendering contract on `TileLayoutView`),
/// while each workspace's chrome — tab strip, seams, empty state, translucency
/// backdrop — is drawn per workspace. Two separate views laying out against the
/// same rectangle have to derive it from the same arithmetic, or the panes drift
/// away from the seams that are supposed to sit between them.
///
/// So the insets live here rather than as `.padding` in either view, and both
/// ask this type.
enum PaneCanvasMetrics {
    static let horizontalInset: CGFloat = AinkradSpacing.sm
    static let topInset: CGFloat = AinkradSpacing.xs
    static let bottomInset: CGFloat = AinkradSpacing.sm

    /// The Focus-Mode tab strip's height. A CONSTANT, not the strip's intrinsic
    /// size: the pane layer has to know how much room the strip takes without
    /// being able to measure it (it isn't in the same view tree), so the strip
    /// is pinned to this and both sides agree by construction.
    static let tabStripHeight: CGFloat = 30
    /// Gap between the strip and the canvas below it.
    static let tabStripSpacing: CGFloat = AinkradSpacing.xs

    /// Vertical space the tab strip occupies when shown, zero when it isn't.
    static func reservedTabStripHeight(showsTabStrip: Bool) -> CGFloat {
        showsTabStrip ? tabStripHeight + tabStripSpacing : 0
    }

    /// The pane canvas rectangle within a workspace frame of `size`.
    static func canvasRect(in size: CGSize, showsTabStrip: Bool) -> CGRect {
        let strip = reservedTabStripHeight(showsTabStrip: showsTabStrip)
        return CGRect(
            x: horizontalInset,
            y: topInset + strip,
            width: max(size.width - horizontalInset * 2, 0),
            height: max(size.height - topInset - strip - bottomInset, 0)
        )
    }

    /// The strip's own rectangle, above the canvas.
    static func tabStripRect(in size: CGSize) -> CGRect {
        CGRect(
            x: horizontalInset,
            y: topInset,
            width: max(size.width - horizontalInset * 2, 0),
            height: tabStripHeight
        )
    }
}
