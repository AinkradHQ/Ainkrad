import AinkradAppKit
import Testing

@testable import Ainkrad

@Suite("OverlayChrome")
struct OverlayChromeTests {
    @Test("chrome corner radius derives from the shared panel radius")
    func cornerRadiusUsesScale() {
        #expect(OverlayChrome.cornerRadius == AinkradRadius.panel)
        #expect(OverlayChrome.cornerRadius == 14)  // behavior-preserving
    }
}
