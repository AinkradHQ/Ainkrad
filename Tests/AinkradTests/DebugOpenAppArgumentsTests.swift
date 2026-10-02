import Testing
import Foundation
@testable import Ainkrad

@Suite("DebugOpenAppArguments")
struct DebugOpenAppArgumentsTests {
    @Test("returns nil when -AinkradOpenApp is absent")
    func absentArgument() {
        let args: [String: String] = [:]
        #expect(parseDebugOpenAppArguments({ args[$0] }) == nil)
    }

    @Test("returns nil when -AinkradOpenApp is empty or whitespace")
    func emptyArgument() {
        let args = ["AinkradOpenApp": "   "]
        #expect(parseDebugOpenAppArguments({ args[$0] }) == nil)
    }

    @Test("parses appID without payload when payload is absent")
    func appIDOnly() {
        let args = ["AinkradOpenApp": "thrall"]
        let result = parseDebugOpenAppArguments({ args[$0] })
        #expect(result?.appID == "thrall")
        #expect(result?.payload == nil)
    }

    @Test("parses appID and trimmed payload when both are present")
    func appIDWithPayload() {
        let args = [
            "AinkradOpenApp": "thrall ",
            "AinkradOpenAppPayload": " payload-data "
        ]
        let result = parseDebugOpenAppArguments({ args[$0] })
        #expect(result?.appID == "thrall")
        #expect(result?.payload == "payload-data")
    }
}
