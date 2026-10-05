import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("CodeSearchRegistration")
@MainActor
struct CodeSearchRegistrationTests {
    @Test func grepAndGlobAreReadClass() {
        let root = FileManager.default.temporaryDirectory
        let registry = AgentToolRegistry(tools: [
            GrepTool(rootProvider: { root }),
            GlobTool(rootProvider: { root }),
        ])
        #expect(registry.tool(named: "grep")?.permission == .read)
        #expect(registry.tool(named: "glob")?.permission == .read)
    }
}
