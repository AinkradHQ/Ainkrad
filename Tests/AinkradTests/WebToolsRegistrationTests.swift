import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("WebToolsRegistration")
@MainActor
struct WebToolsRegistrationTests {
    @Test func webToolsAreReadClass() {
        let registry = AgentToolRegistry(tools: [
            WebFetchTool(http: RedirectValidatingHTTPClient()),
            WebSearchTool(
                backend: BraveSearchBackend(secrets: InMemorySecretStore(), http: URLSessionDataHTTPClient())),
        ])
        #expect(registry.tool(named: "web_fetch")?.permission == .read)
        #expect(registry.tool(named: "web_search")?.permission == .read)
    }

    @Test func webToolsAreExcludedFromUnattendedRegistries() {
        let fetch = WebFetchTool(http: RedirectValidatingHTTPClient())
        let search = WebSearchTool(
            backend: BraveSearchBackend(secrets: InMemorySecretStore(), http: URLSessionDataHTTPClient()))
        let read = ReadFileTool()
        // The production predicate itself:
        #expect(AppEnvironment.isUnattendedNetworkTool(fetch))
        #expect(AppEnvironment.isUnattendedNetworkTool(search))
        #expect(!AppEnvironment.isUnattendedNetworkTool(read))
        // Applied like the background/subagent derivation does:
        let unattended = AgentToolRegistry(
            tools: [fetch, search, read].filter { !AppEnvironment.isUnattendedNetworkTool($0) })
        #expect(unattended.tool(named: "web_fetch") == nil)
        #expect(unattended.tool(named: "web_search") == nil)
        #expect(unattended.tool(named: "read_file") != nil)
    }
}
