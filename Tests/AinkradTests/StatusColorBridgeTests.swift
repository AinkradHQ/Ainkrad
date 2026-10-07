import AinkradAppKit
import AinkradHostRuntime
import Testing

@testable import Ainkrad

@Suite("Status color bridge")
struct StatusColorBridgeTests {
    @Test("every theme carries distinct status colors through the ABI-safe AinkradStatusColors bridge")
    func bridged() {
        for theme in Theme.allCases {
            let t = theme.skin
            let statusColors = AinkradStatusColors(success: t.color(\.success), warning: t.color(\.warning), danger: t.color(\.danger))
            #expect(statusColors.success != statusColors.danger)
            #expect(statusColors.warning != t.color(\.background))
        }
    }
}
