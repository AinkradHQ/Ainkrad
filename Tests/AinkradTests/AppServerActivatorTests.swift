import AinkradAppKit
import Foundation
import Testing

@testable import Ainkrad
@testable import AinkradHostRuntime

@MainActor
@Suite("AppServerActivator")
struct AppServerActivatorTests {
    /// A server that answers `initialize` and records how many calls it saw.
    final class Counter { var calls = 0 }

    func makeServer(_ counter: Counter) -> MCPAppServer {
        let server = MCPAppServer(appID: "demo")
        server.addTool(
            .init(
                name: "ping", description: "Ping.",
                schemaJSON: #"{"type":"object"}"#, readOnly: true
            ) { _ in
                counter.calls += 1
                return AgentActionResult(text: "pong", isError: false)
            })
        return server
    }

    let callPing = #"{"jsonrpc":"2.0","id":"1","method":"tools/call","params":{"name":"ping","arguments":{}}}"#

    /// Stands in for an app that declared `requiresLiveApp` on every tool. The
    /// activator's own default is the opposite (`false` everywhere), so the
    /// tests that exercise the OPEN path must opt in explicitly — that is the
    /// point of the change: opening is now the app's claim, not the method's.
    let needsWindow: (String, String, String) -> Bool = { _, _, _ in true }

    @Test("dispatches straight through when the app is already open", .timeLimit(.minutes(1)))
    func dispatchesWhenOpen() async throws {
        let counter = Counter()
        var openRequests: [String] = []
        let activator = AppServerActivator(
            servers: ["demo": makeServer(counter)],
            isAppOpen: { _ in true },
            requestOpen: { openRequests.append($0) },
            availability: { _ in .available })
        let reply = try await activator.dispatch(appID: "demo", message: callPing)
        #expect(reply.contains("pong"))
        #expect(counter.calls == 1)
        #expect(openRequests.isEmpty)  // no launch needed
    }

    @Test("opens a closed app, then dispatches", .timeLimit(.minutes(1)))
    func opensClosedApp() async throws {
        let counter = Counter()
        var opened = false
        var launched: [String] = []
        let activator = AppServerActivator(
            servers: ["demo": makeServer(counter)],
            isAppOpen: { _ in opened },
            requestOpen: { _ in opened = true },  // the host opens it synchronously here
            availability: { _ in .available },
            requiresLiveApp: needsWindow,
            launchTimeout: .seconds(2),
            onLaunch: { launched.append($0) })
        let reply = try await activator.dispatch(appID: "demo", message: callPing)
        #expect(reply.contains("pong"))
        #expect(launched == ["demo"])  // timeline event fired exactly once
    }

    /// Finding 1: launch-time `connectEnabled()` sends `initialize` to every
    /// enabled config. If that force-opened the app, every MCP-publishing app
    /// would pop open on every launch.
    @Test("initialize against a closed app never requests an open", .timeLimit(.minutes(1)))
    func metadataMethodsDoNotOpenTheApp() async throws {
        let counter = Counter()
        var openRequests: [String] = []
        let activator = AppServerActivator(
            servers: ["demo": makeServer(counter)],
            isAppOpen: { _ in false },  // closed, and stays closed
            requestOpen: { openRequests.append($0) },
            availability: { _ in .available },
            launchTimeout: .milliseconds(200))
        for method in ["initialize", "tools/list", "resources/list"] {
            let reply = try await activator.dispatch(
                appID: "demo",
                message: #"{"jsonrpc":"2.0","id":"1","method":"\#(method)","params":{}}"#)
            #expect(reply.contains("\"result\""))
        }
        #expect(openRequests.isEmpty)
    }

    @Test(
        "an unparseable message dispatches without opening the app",
        .timeLimit(.minutes(1)))
    func garbageDoesNotOpenTheApp() async throws {
        let counter = Counter()
        var openRequests: [String] = []
        let activator = AppServerActivator(
            servers: ["demo": makeServer(counter)],
            isAppOpen: { _ in false },
            requestOpen: { openRequests.append($0) },
            availability: { _ in .available },
            launchTimeout: .milliseconds(200))
        let reply = try await activator.dispatch(appID: "demo", message: "not json")
        #expect(reply.contains("-32700"))  // the server's own parse error
        #expect(openRequests.isEmpty)
    }

    /// THE regression. The gate used to be per-METHOD, so every `tools/call`
    /// force-opened the app: asking the assistant to create a Lore note popped
    /// Lore's window open. A tool that never claimed it needs a window must be
    /// dispatched against a CLOSED app, in the background, with no open request
    /// and no launch wait.
    @Test(
        "a background tool call against a closed app never opens it",
        .timeLimit(.minutes(1)))
    func backgroundToolCallDoesNotOpenTheApp() async throws {
        let counter = Counter()
        var openRequests: [String] = []
        var launched: [String] = []
        let activator = AppServerActivator(
            servers: ["demo": makeServer(counter)],
            isAppOpen: { _ in false },  // closed, and stays closed
            requestOpen: { openRequests.append($0) },
            availability: { _ in .available },
            // The default the host now ships with: nothing declares it.
            launchTimeout: .milliseconds(200),
            onLaunch: { launched.append($0) })
        let reply = try await activator.dispatch(appID: "demo", message: callPing)
        #expect(reply.contains("pong"))  // the handler actually ran
        #expect(counter.calls == 1)
        #expect(openRequests.isEmpty)  // …with no window popped open
        #expect(launched.isEmpty)  // …and no launch event
    }

    /// The other half: an app that DOES declare a tool needs its window still
    /// gets one. Guards against "fixed the pop-open by never opening at all".
    @Test("only the declaring tool opens the app", .timeLimit(.minutes(1)))
    func onlyDeclaredToolsOpenTheApp() async throws {
        let counter = Counter()
        var opened = false
        var openRequests: [String] = []
        let activator = AppServerActivator(
            servers: ["demo": makeServer(counter)],
            isAppOpen: { _ in opened },
            requestOpen: {
                openRequests.append($0)
                opened = true
            },
            availability: { _ in .available },
            requiresLiveApp: { _, _, name in name == "ping" },
            launchTimeout: .seconds(2))
        _ = try await activator.dispatch(appID: "demo", message: callPing)
        #expect(openRequests == ["demo"])
    }

    /// A `tools/call` with no `name` has nothing to look a flag up by, and the
    /// server will reject it anyway — so it must not launch an app either.
    @Test("a tools/call with no name never opens the app", .timeLimit(.minutes(1)))
    func namelessToolCallDoesNotOpenTheApp() async throws {
        let counter = Counter()
        var openRequests: [String] = []
        let activator = AppServerActivator(
            servers: ["demo": makeServer(counter)],
            isAppOpen: { _ in false },
            requestOpen: { openRequests.append($0) },
            availability: { _ in .available },
            requiresLiveApp: needsWindow,
            launchTimeout: .milliseconds(200))
        let reply = try await activator.dispatch(
            appID: "demo",
            message: #"{"jsonrpc":"2.0","id":"1","method":"tools/call","params":{}}"#)
        #expect(reply.contains("-32602"))
        #expect(openRequests.isEmpty)
    }

    @Test("tools/call against a closed app still opens it first", .timeLimit(.minutes(1)))
    func toolsCallStillOpensTheApp() async throws {
        let counter = Counter()
        var opened = false
        var openRequests: [String] = []
        let activator = AppServerActivator(
            servers: ["demo": makeServer(counter)],
            isAppOpen: { _ in opened },
            requestOpen: {
                openRequests.append($0)
                opened = true
            },
            availability: { _ in .available },
            requiresLiveApp: needsWindow,
            launchTimeout: .seconds(2))
        let reply = try await activator.dispatch(appID: "demo", message: callPing)
        #expect(reply.contains("pong"))
        #expect(openRequests == ["demo"])
    }

    /// Finding 4: `Task.sleep` returns immediately once cancelled, so without an
    /// explicit `checkCancellation` the poll loop busy-spins the MAIN ACTOR for
    /// the whole timeout. Asserts it gives up in well under that timeout.
    @Test(
        "a cancelled dispatch returns promptly instead of spinning out the timeout",
        .timeLimit(.minutes(1)))
    func cancelledDispatchReturnsPromptly() async {
        let counter = Counter()
        let activator = AppServerActivator(
            servers: ["demo": makeServer(counter)],
            isAppOpen: { _ in false },  // never opens
            requestOpen: { _ in },
            availability: { _ in .available },
            requiresLiveApp: needsWindow,
            launchTimeout: .seconds(30))  // far longer than we will wait
        let start = ContinuousClock.now
        let task = Task { try await activator.dispatch(appID: "demo", message: callPing) }
        task.cancel()
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test("fails with notInstalled when the app is unknown", .timeLimit(.minutes(1)))
    func failsWhenNotInstalled() async {
        let activator = AppServerActivator(
            servers: [:], isAppOpen: { _ in false }, requestOpen: { _ in },
            availability: { _ in .unknown })
        await #expect(throws: AppDispatchFailure.notInstalled("ghost")) {
            try await activator.dispatch(appID: "ghost", message: callPing)
        }
    }

    @Test("fails with disabled when the app is switched off", .timeLimit(.minutes(1)))
    func failsWhenDisabled() async {
        let counter = Counter()
        let activator = AppServerActivator(
            servers: ["demo": makeServer(counter)],
            isAppOpen: { _ in false }, requestOpen: { _ in },
            availability: { _ in .disabled },
            requiresLiveApp: needsWindow)
        await #expect(throws: AppDispatchFailure.disabled("demo")) {
            try await activator.dispatch(appID: "demo", message: callPing)
        }
    }

    /// The cache is memoized for the process lifetime, so a torn-down app must
    /// evict it — otherwise the next dispatch runs against a server built over
    /// the CLOSED instance's state, and that instance is pinned forever.
    @Test(
        "evicting drops the cached server and the next use builds a fresh one",
        .timeLimit(.minutes(1)))
    func evictionRebuildsTheServer() async throws {
        let counter = Counter()
        var built = 0
        let activator = AppServerActivator(
            serverFor: { _ in
                built += 1
                return self.makeServer(counter)
            },
            isAppOpen: { _ in true }, requestOpen: { _ in },
            availability: { _ in .available })

        _ = try await activator.dispatch(appID: "demo", message: callPing)
        _ = try await activator.dispatch(appID: "demo", message: callPing)
        #expect(built == 1, "the server must be memoized across dispatches")

        activator.evict(appID: "demo")
        _ = try await activator.dispatch(appID: "demo", message: callPing)
        #expect(built == 2, "after eviction the next dispatch must resolve a fresh server")
        // And the fresh one is cached in turn, not rebuilt per call.
        _ = try await activator.dispatch(appID: "demo", message: callPing)
        #expect(built == 2)
    }

    @Test("evicting an app that was never cached is a no-op", .timeLimit(.minutes(1)))
    func evictingUnknownAppIsHarmless() async throws {
        let counter = Counter()
        let activator = AppServerActivator(
            servers: ["demo": makeServer(counter)],
            isAppOpen: { _ in true }, requestOpen: { _ in },
            availability: { _ in .available })
        activator.evict(appID: "ghost")
        let reply = try await activator.dispatch(appID: "demo", message: callPing)
        #expect(reply.contains("pong"))
    }

    @Test("fails with launchTimedOut when the app never opens", .timeLimit(.minutes(1)))
    func failsWhenLaunchTimesOut() async {
        let counter = Counter()
        let activator = AppServerActivator(
            servers: ["demo": makeServer(counter)],
            isAppOpen: { _ in false },  // never becomes open
            requestOpen: { _ in },
            availability: { _ in .available },
            requiresLiveApp: needsWindow,
            launchTimeout: .milliseconds(200))
        await #expect(throws: AppDispatchFailure.launchTimedOut("demo")) {
            try await activator.dispatch(appID: "demo", message: callPing)
        }
        #expect(counter.calls == 0)
    }
}
