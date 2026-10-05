import AinkradAppKit
// Tests/AinkradTests/AppMCPOpenStateTests.swift
import Foundation
import Testing

@testable import Ainkrad
@testable import AinkradHostRuntime

/// Regression cover for the open-state seam the app-hosted MCP activator asks
/// "do I need to launch this app first?" through.
///
/// The bug this exists to prevent: `isAppOpen` once consulted only
/// `WorkspaceManager`, so an `.overlay`-presentation app — which never gets a
/// `tileLayout` block, only `AppEnvironment.presentedOverlayAppID` — reported
/// as closed even while presented. Every dispatch to it then requested a launch
/// it didn't need and polled out the full launch timeout, failing with
/// `launchTimedOut` against a server that was reachable the whole time.
@Suite("App MCP open state")
@MainActor
struct AppMCPOpenStateTests {
    func bootstrapEnvironment() -> AppEnvironment {
        // Leaked deliberately, as before: these tests hold the environment past
        // the helper's return, so there is no scope to run a cleanup in.
        let t = TestHome.make("mcp-openstate")
        return AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)
    }

    @Test("an overlay-presented app counts as open even with no tiled block")
    func overlayAppIsOpen() {
        let environment = bootstrapEnvironment()
        environment.presentedOverlayAppID = "overlay-app"

        // The regression itself: no block exists for it anywhere...
        #expect(!environment.workspaceManager.isAppTiled("overlay-app"))
        // ...yet the app is open, so no launch is needed.
        #expect(environment.isAppOpen("overlay-app"))
    }

    @Test("a tiled app counts as open, in any workspace")
    func tiledAppIsOpen() {
        let environment = bootstrapEnvironment()
        let other = environment.workspaceManager.createWorkspace()
        other.tileLayout.openApp("tiled-app")
        environment.workspaceManager.switchTo(environment.workspaceManager.workspaces[0].id)

        #expect(environment.isAppOpen("tiled-app"))  // inactive workspace still counts
    }

    @Test("an app that is neither tiled nor presented is closed")
    func unknownAppIsClosed() {
        let environment = bootstrapEnvironment()
        #expect(!environment.isAppOpen("ghost"))
    }

    /// End-to-end over the seam the activator actually uses: the launch hub's
    /// open-state provider, wired exactly as `finalizeBootstrap` wires it.
    /// Proves the overlay case dispatches immediately instead of timing out.
    @Test("dispatch to an overlay-presented app never requests a launch", .timeLimit(.minutes(1)))
    func dispatchesToOverlayAppWithoutLaunching() async throws {
        let environment = bootstrapEnvironment()
        environment.presentedOverlayAppID = "demo"

        let hub = PluginLaunchHub()
        hub.setOpenStateProvider { [weak environment] appID in
            environment?.isAppOpen(appID) ?? false
        }

        let server = MCPAppServer(appID: "demo")
        server.addTool(
            .init(
                name: "ping", description: "Ping.",
                schemaJSON: #"{"type":"object"}"#, readOnly: true
            ) { _ in
                AgentActionResult(text: "pong", isError: false)
            })
        var openRequests: [String] = []
        let activator = AppServerActivator(
            servers: ["demo": server],
            isAppOpen: { hub.isOpen($0) },
            requestOpen: { openRequests.append($0) },  // never opens it, so a
            availability: { _ in .available },  // launch would time out
            launchTimeout: .milliseconds(200))

        let reply = try await activator.dispatch(
            appID: "demo",
            message: #"{"jsonrpc":"2.0","id":"1","method":"tools/call","params":{"name":"ping","arguments":{}}}"#)
        #expect(reply.contains("pong"))
        #expect(openRequests.isEmpty)
    }
}
