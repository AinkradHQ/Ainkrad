import AinkradAppKit
import Testing

@testable import Ainkrad

@MainActor
@Suite("HoardApp registration")
struct HoardAppRegistrationTests {
    @Test("declares its identity")
    func identity() {
        #expect(HoardApp.id == "hoard")
        #expect(HoardApp.displayName == "Hoard")
        #expect(HoardApp.icon == "folder")
    }
}
