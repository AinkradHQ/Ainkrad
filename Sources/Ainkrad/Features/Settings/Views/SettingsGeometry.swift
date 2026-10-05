import AinkradAppKit
import CoreGraphics

/// Panel sizing for the Settings overlay. Isolated from the view so the
/// later user-resizable pass has one place to grow into, and so the
/// clamping is testable without a window.
enum SettingsGeometry {
    static func panelSize(in container: CGSize) -> CGSize {
        CGSize(
            width: min(
                max(
                    SettingsMetrics.panelMinWidth,
                    container.width * SettingsMetrics.panelWidthFraction),
                SettingsMetrics.panelMaxWidth),
            height: min(
                max(
                    SettingsMetrics.panelMinHeight,
                    container.height * SettingsMetrics.panelHeightFraction),
                SettingsMetrics.panelMaxHeight))
    }
}
