import AinkradAppKit
import AinkradHostRuntime
import Testing

@testable import Ainkrad

@Suite("Status color bridge")
@MainActor
struct StatusColorBridgeTests {
    @Test("every theme carries distinct status colors through the ABI-safe AinkradStatusColors bridge")
    func bridged() {
        for theme in neonSchemeIDs {
            let t = NeonSchemes.skin(theme)
            let statusColors = AinkradStatusColors(success: t.color(\.success), warning: t.color(\.warning), danger: t.color(\.danger))
            #expect(statusColors.success != statusColors.danger)
            #expect(statusColors.warning != t.color(\.background))
        }
    }
}
