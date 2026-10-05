import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("JSONValue")
struct JSONValueTests {
    @Test("round-trips a nested object through encode/decode")
    func roundTripsNestedObject() throws {
        let json = Data(#"{"a":1,"b":true,"c":"x","d":null,"e":[1,2],"f":{"g":3.5}}"#.utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: json)
        let reencoded = try JSONEncoder().encode(value)
        let again = try JSONDecoder().decode(JSONValue.self, from: reencoded)
        #expect(value == again)
    }

    @Test("decodes bool and number as distinct cases")
    func distinguishesBoolAndNumber() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(#"[true,1]"#.utf8))
        #expect(value == .array([.bool(true), .number(1)]))
    }
}
