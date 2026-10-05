import AinkradAppKit
import SwiftUI
import Testing

@testable import AinkradHostRuntime

@MainActor
@Suite("App MCP registration")
struct AppMCPRegistrationTests {
    @Test("an app that does not conform gets a nil factory")
    func nonConformingAppHasNoFactory() {
        let app = RegisteredApp(
            id: "plain", displayName: "Plain", icon: "circle",
            isEnabledByDefault: true, source: .builtIn,
            makeRootView: { AnyView(EmptyView()) },
            makeSettingsView: { AnyView(EmptyView()) },
            chromeFill: { nil })
        #expect(app.mcpServerFactory == nil)
    }

    @Test("a factory set on the app is retained and returns the server")
    func factoryIsRetained() {
        var app = RegisteredApp(
            id: "demo", displayName: "Demo", icon: "circle",
            isEnabledByDefault: true, source: .builtIn,
            makeRootView: { AnyView(EmptyView()) },
            makeSettingsView: { AnyView(EmptyView()) },
            chromeFill: { nil })
        app.mcpServerFactory = { MCPAppServer(appID: "demo") }
        guard let factory = app.mcpServerFactory else {
            Issue.record("no factory")
            return
        }
        #expect(factory().appID == "demo")
    }
}
