import Foundation
import Testing

@testable import Ainkrad

@Suite("MCP catalog model")
struct MCPCatalogModelTests {
    @Test func decodesLegacyPluginEntryAsPluginKind() throws {
        let json = """
            {"appID":"x","displayName":"X","icon":"app","description":"d","version":"1.0",
             "apiVersion":4,"downloadURL":"https://e/x.zip","sha256":"abc","sourceRepo":"o/r"}
            """.data(using: .utf8)!
        let entry = try JSONDecoder().decode(CatalogEntry.self, from: json)
        #expect(entry.kind == .plugin)
        #expect(entry.mcp == nil)
    }

    @Test func decodesMCPServerEntry() throws {
        let json = """
            {"appID":"web-search","displayName":"Web Search","icon":"magnifyingglass",
             "description":"search the web","version":"1.0","apiVersion":0,
             "downloadURL":"https://e/none","sha256":"","sourceRepo":"o/r","kind":"mcpServer",
             "mcp":{"transport":"stdio","command":"npx","args":["-y","srv"],
                    "envKeys":["API_KEY"],"headerKeys":[]}}
            """.data(using: .utf8)!
        let entry = try JSONDecoder().decode(CatalogEntry.self, from: json)
        #expect(entry.kind == .mcpServer)
        #expect(entry.mcp?.transport == .stdio)
        #expect(entry.mcp?.command == "npx")
        #expect(entry.mcp?.envKeys == ["API_KEY"])
    }

    @Test func roundTripsThroughRemoteCatalog() throws {
        let json = """
            {"apps":[{"appID":"s","displayName":"S","icon":"i","description":"d","version":"1",
              "apiVersion":0,"downloadURL":"https://e/n","sha256":"","sourceRepo":"o/r",
              "kind":"mcpServer","mcp":{"transport":"httpSSE","url":"https://mcp.example/api",
              "args":[],"envKeys":[],"headerKeys":["Authorization"]}}]}
            """.data(using: .utf8)!
        let catalog = try JSONDecoder().decode(RemoteCatalog.self, from: json)
        #expect(catalog.apps.first?.mcp?.url?.absoluteString == "https://mcp.example/api")
        #expect(catalog.apps.first?.mcp?.headerKeys == ["Authorization"])
    }

    @Test func isValidMCPEntryRejectsMalformedStdioEntry() throws {
        // stdio transport with no command should be invalid, not crash.
        let entry = CatalogEntry(
            appID: "bad", displayName: "Bad", icon: "app", description: "d", version: "1.0",
            apiVersion: 0, downloadURL: URL(string: "https://e/none")!, sha256: "", sourceRepo: "o/r",
            kind: .mcpServer,
            mcp: MCPCatalogDescriptor(transport: .stdio, command: nil)
        )
        #expect(entry.isValidMCPEntry == false)
    }

    @Test func isValidMCPEntryRejectsNonHTTPSURL() throws {
        let entry = CatalogEntry(
            appID: "bad2", displayName: "Bad2", icon: "app", description: "d", version: "1.0",
            apiVersion: 0, downloadURL: URL(string: "https://e/none")!, sha256: "", sourceRepo: "o/r",
            kind: .mcpServer,
            mcp: MCPCatalogDescriptor(transport: .httpSSE, url: URL(string: "http://insecure.example"))
        )
        #expect(entry.isValidMCPEntry == false)
    }

    @Test func isValidMCPEntryAcceptsWellFormedEntries() throws {
        let stdio = CatalogEntry(
            appID: "ok1", displayName: "Ok1", icon: "app", description: "d", version: "1.0",
            apiVersion: 0, downloadURL: URL(string: "https://e/none")!, sha256: "", sourceRepo: "o/r",
            kind: .mcpServer,
            mcp: MCPCatalogDescriptor(transport: .stdio, command: "npx")
        )
        #expect(stdio.isValidMCPEntry == true)

        let http = CatalogEntry(
            appID: "ok2", displayName: "Ok2", icon: "app", description: "d", version: "1.0",
            apiVersion: 0, downloadURL: URL(string: "https://e/none")!, sha256: "", sourceRepo: "o/r",
            kind: .mcpServer,
            mcp: MCPCatalogDescriptor(transport: .httpSSE, url: URL(string: "https://mcp.example/api"))
        )
        #expect(http.isValidMCPEntry == true)
    }

    @Test func isValidMCPEntryFalseForPluginKind() throws {
        let entry = CatalogEntry(
            appID: "p", displayName: "P", icon: "app", description: "d", version: "1.0",
            apiVersion: 0, downloadURL: URL(string: "https://e/x.zip")!, sha256: "abc", sourceRepo: "o/r"
        )
        #expect(entry.isValidMCPEntry == false)
    }
}
