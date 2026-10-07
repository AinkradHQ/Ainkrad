import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("JSONValue tool helpers")
struct JSONValueToolHelpersTests {
    @Test func parseThenReadFields() {
        let v = JSONValue.parse(#"{"path":"/tmp/a.txt","n":3}"#)
        #expect(v?["path"]?.stringValue == "/tmp/a.txt")
    }

    @Test func toFoundationObjectRoundTrips() throws {
        let v = JSONValue.object(["a": .string("x"), "b": .number(2)])
        let obj = v.toFoundationObject()
        let data = try JSONSerialization.data(withJSONObject: obj)
        let back = JSONValue.parse(String(decoding: data, as: UTF8.self))
        #expect(back?["a"]?.stringValue == "x")
    }

    @Test func toolEventsAreEquatable() {
        #expect(
            AgentEvent.toolUseStart(id: "1", name: "read_file")
                == AgentEvent.toolUseStart(id: "1", name: "read_file"))
    }
}
