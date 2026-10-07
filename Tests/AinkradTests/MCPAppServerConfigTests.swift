import Foundation
import Testing

@testable import Ainkrad

@Suite("MCPServerConfig in-process")
struct MCPAppServerConfigTests {
    @Test("an in-process config round-trips through Codable")
    func roundTrip() throws {
        let config = MCPServerConfig(
            id: "gitmage", displayName: "Git Mage", transport: .inProcess,
            enabled: true, trusted: false, appID: "gitmage")
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(MCPServerConfig.self, from: data)
        #expect(decoded == config)
        #expect(decoded.transport == .inProcess)
        #expect(decoded.appID == "gitmage")
    }

    @Test("a legacy payload without appID still decodes")
    func legacyPayloadDecodes() throws {
        let json =
            #"{"id":"brave","displayName":"Brave","transport":"stdio","args":[],"envKeys":[],"headerKeys":[],"enabled":true,"trusted":false}"#
        let decoded = try JSONDecoder().decode(
            MCPServerConfig.self,
            from: try #require(json.data(using: .utf8)))
        #expect(decoded.appID == nil)
        #expect(decoded.transport == .stdio)
    }
}
