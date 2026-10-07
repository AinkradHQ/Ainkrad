import AinkradAppKit
import CoreGraphics
import Testing

@testable import Ainkrad

@Suite("Settings panel geometry")
struct SettingsGeometryTests {
    @Test("the panel clamps between its floor and ceiling")
    func clamping() {
        let small = SettingsGeometry.panelSize(in: CGSize(width: 800, height: 600))
        #expect(small.width == SettingsMetrics.panelMinWidth)
        #expect(small.height == SettingsMetrics.panelMinHeight)

        let huge = SettingsGeometry.panelSize(in: CGSize(width: 4000, height: 3000))
        #expect(huge.width == SettingsMetrics.panelMaxWidth)
        #expect(huge.height == SettingsMetrics.panelMaxHeight)
    }

    @Test("between the bounds it tracks the container fractions")
    func tracksFractions() {
        let size = SettingsGeometry.panelSize(in: CGSize(width: 1600, height: 1000))
        #expect(size.width == 1600 * SettingsMetrics.panelWidthFraction)
        #expect(size.height == 1000 * SettingsMetrics.panelHeightFraction)
    }

    @Test("the panel is larger than the pre-overhaul envelope")
    func isLarger() {
        let size = SettingsGeometry.panelSize(in: CGSize(width: 1600, height: 1000))
        #expect(size.width > 1040)
        #expect(size.height > 720)
    }
}
