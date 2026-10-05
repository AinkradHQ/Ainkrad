// Tests/AinkradTests/AgentProfileTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("AgentProfile")
struct AgentProfileTests {
    @Test func customFactorySaneDefaults() {
        let a = AgentProfile.custom(name: "Reviewer", instructions: "Review carefully.")
        #expect(a.builtin == false)
        #expect(a.toolPolicy == .all)
        #expect(a.routing.routerEnabled)
        #expect(a.routing.maxTier == nil)
        #expect(a.permissionPosture == nil)  // nil = inherit workspace mode
    }

    @Test func codableRoundTrips() throws {
        var a = AgentProfile.custom(name: "R", instructions: "x")
        a.routing = AgentRouting(
            routerEnabled: false, preferredModels: ["m"], allowedModels: ["m"], maxTier: .cheapPaid)
        a.defaultModel = "gpt-5-mini"
        a.icon = "wand.and.stars"
        let data = try JSONEncoder().encode(a)
        #expect(try JSONDecoder().decode(AgentProfile.self, from: data) == a)
    }

    /// Old persisted agents (pre-icon field) must decode to the default icon,
    /// not throw, so upgrading the app never corrupts/loses existing agent data.
    @Test func decodesOldPayloadWithoutIconToDefault() throws {
        let current = AgentProfile.custom(name: "Legacy", instructions: "do stuff")
        var json =
            try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(current)) as! [String: Any]
        #expect(json["icon"] != nil)  // sanity: current encode does include it
        json.removeValue(forKey: "icon")

        let oldData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(AgentProfile.self, from: oldData)

        #expect(decoded.icon == "sparkles")
        #expect(decoded.name == "Legacy")
    }
}
