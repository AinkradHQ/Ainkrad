import AinkradAppKit
import CoreGraphics

extension AinkradSkin {
    /// Tracking for a caps label: `tracking` while the theme uppercases labels,
    /// none when `type.labelCase` is `none` (Glass), where caps tracking reads wrong.
    func labelKerning(_ tracking: CGFloat) -> CGFloat {
        type.labelCase == "none" ? 0 : tracking
    }
}
