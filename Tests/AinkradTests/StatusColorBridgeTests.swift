import AinkradAppKit
import AinkradHostRuntime
import Testing

@testable import Ainkrad

@Suite("Status color bridge")
struct StatusColorBridgeTests {
    @Test("every theme carries distinct status colors through the ABI-safe AinkradStatusColors bridge")
    func bridged() {
        for theme in Theme.allCases {
            let t = theme.tokens
            let statusColors = AinkradStatusColors(success: t.success, warning: t.warning, danger: t.danger)
            #expect(statusColors.success != statusColors.danger)
            #expect(statusColors.warning != t.background)
        }
    }
}
