import AinkradAppKit
import Testing

@testable import Ainkrad

@Suite("Overlay pane mode")
struct OverlayModeSelectionTests {
    @Test("An unswitched overlay follows the resolved default")
    func followsDefault() {
        let selection = OverlayModeSelection()
        #expect(selection.resolved(default: .basic) == .basic)
        #expect(selection.resolved(default: .advanced) == .advanced)
    }

    @Test("The setter flips a basic overlay to advanced and back")
    func roundTrip() {
        var selection = OverlayModeSelection()
        selection.switched = .advanced
        #expect(selection.resolved(default: .basic) == .advanced)
        selection.switched = .basic
        #expect(selection.resolved(default: .basic) == .basic)
    }
}
