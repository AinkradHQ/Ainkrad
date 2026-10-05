import AinkradAppKit
import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@MainActor
@Suite("RunTerminalTool")
struct RunTerminalToolTests {
    private func obj(_ d: [String: JSONValue]) -> JSONValue { .object(d) }

    /// A host-only router — `.mainInteractive` (the tool's default trust
    /// tier) always resolves to `HostBackend`, so these tests exercise the
    /// exact same argv/capture/timeout path the tool used to spawn directly.
    private func hostRouter() -> ExecutionRouter {
        ExecutionRouter(
            profiles: SandboxProfileStore(persistence: InMemoryPersistenceStore()),
            backends: [.host: HostBackend()])
    }

    @Test("captures stdout of a command")
    func capturesOutput() async throws {
        let hub = AgentActionRegistryHub()
        let router = hostRouter()
        let tool = RunTerminalTool(actionHub: hub, router: router)
        let result = try await tool.execute(obj(["command": .string("echo hello-ainkrad")]))
        #expect(!result.isError)
        #expect(result.content.contains("hello-ainkrad"))
    }

    @Test("dispatches a terminal.echo action with command + output")
    func dispatchesEcho() async throws {
        let hub = AgentActionRegistryHub()
        let router = hostRouter()
        var received: String?
        _ = hub.register(appID: "terminal", actionID: "terminal.echo") { json in
            received = json
            return AgentActionResult(text: "ok", isError: false)
        }
        let tool = RunTerminalTool(actionHub: hub, router: router)
        _ = try await tool.execute(obj(["command": .string("echo hi")]))
        let json = try #require(received)
        #expect(json.contains("\"command\""))
        #expect(json.contains("hi"))
    }

    @Test("missing echo handler is a no-op (best effort)")
    func echoNoOp() async throws {
        let hub = AgentActionRegistryHub()  // nothing registered
        let router = hostRouter()
        let tool = RunTerminalTool(actionHub: hub, router: router)
        let result = try await tool.execute(obj(["command": .string("echo ok")]))
        #expect(!result.isError)
    }

    @Test("flags destructive commands irreversible")
    func irreversible() {
        let tool = RunTerminalTool(actionHub: AgentActionRegistryHub(), router: hostRouter())
        #expect(tool.isIrreversible(obj(["command": .string("rm -rf /tmp/x")])))
        #expect(tool.isIrreversible(obj(["command": .string("dd if=/dev/zero of=x")])))
        #expect(!tool.isIrreversible(obj(["command": .string("ls -la")])))
    }

    @Test("a hung/never-terminating command is force-killed at the timeout, not left to hang")
    func timesOutOnHungCommand() async throws {
        let hub = AgentActionRegistryHub()
        let router = hostRouter()
        var tool = RunTerminalTool(actionHub: hub, router: router)
        tool.timeout = 1
        let start = Date()
        let result = try await tool.execute(obj(["command": .string("sleep 5")]))
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 4, "expected the 1s timeout to fire, not the full 5s sleep (elapsed: \(elapsed)s)")
        #expect(result.isError)
        #expect(result.content.contains("[terminated: exceeded 1.0s]"))
    }

    @Test("a command that traps SIGTERM and SIGINT returns instead of crashing on terminationStatus")
    func unresponsiveCommandReturnsInsteadOfCrashing() async throws {
        // Regression test: reading `Process.terminationStatus` while the process is
        // still `isRunning` raises NSInvalidArgumentException and crashes the host.
        // A command that ignores both SIGTERM and SIGINT is still running when the
        // last-resort fallback fires, so the tool must detect that and avoid the read.
        let hub = AgentActionRegistryHub()
        let router = hostRouter()
        var tool = RunTerminalTool(actionHub: hub, router: router)
        tool.timeout = 1
        let start = Date()
        let result = try await tool.execute(obj(["command": .string("trap '' TERM INT; sleep 100")]))
        let elapsed = Date().timeIntervalSince(start)
        // 1s timeout + 0.5s SIGTERM grace + 0.5s SIGINT grace ≈ 2s; give generous headroom
        // but still bound well under the 100s sleep so a regression that hangs is caught.
        #expect(elapsed < 6, "expected the fallback to resume promptly, not hang (elapsed: \(elapsed)s)")
        #expect(result.isError)
        #expect(result.content.contains("[terminated: exceeded 1.0s; process unresponsive to SIGTERM/SIGINT]"))
    }
}

@Suite("RunTerminalTool routing")
@MainActor
struct RunTerminalToolRoutingTests {
    // The tool holds the hub + router `unowned`, so the context struct keeps
    // strong references alive for the test body (an inline temporary would
    // deallocate and trap on first access).
    private struct Context {
        let hub: AgentActionRegistryHub
        let router: ExecutionRouter
        var tool: RunTerminalTool
    }

    private func makeContext(tier: TrustTier) -> Context {
        let hub = AgentActionRegistryHub()
        let router = ExecutionRouter(
            profiles: SandboxProfileStore(persistence: InMemoryPersistenceStore()),
            backends: [
                .host: HostBackend(),
                .seatbelt: SeatbeltBackend(),
            ])
        var tool = RunTerminalTool(actionHub: hub, router: router)
        tool.trustTier = tier
        return Context(hub: hub, router: router, tool: tool)
    }

    @Test func mainSessionRunsAndCaptures() async throws {
        let ctx = makeContext(tier: .mainInteractive)
        let r = try await ctx.tool.execute(.object(["command": .string("echo routed")]))
        #expect(r.content.contains("routed"))
        #expect(!r.isError)
    }

    @Test func backgroundTierRunsSandboxed() async throws {
        // Only assert routing happens; on a box without sandbox-exec, HostBackend
        // is not used for background — the seatbelt backend must be selected.
        guard await SeatbeltBackend().isAvailable() else { return }  // guard-skip
        let ctx = makeContext(tier: .background)
        let r = try await ctx.tool.execute(
            .object([
                "command": .string("echo sandboxed"),
                "working_dir": .string(NSTemporaryDirectory()),
            ]))
        #expect(r.content.contains("sandboxed"))
    }

    @Test func stillReportsExitCode() async throws {
        let ctx = makeContext(tier: .mainInteractive)
        let r = try await ctx.tool.execute(.object(["command": .string("exit 4")]))
        #expect(r.isError)
        #expect(r.content.contains("exit 4"))
    }

    @Test("router failure returns a failed result, never an unsandboxed fallback")
    func routerFailureFailsClosed() async throws {
        let hub = AgentActionRegistryHub()
        // No backends registered at all: any tier's resolved profile has an
        // unregistered backend, so `route` must throw `.backendUnavailable`.
        let router = ExecutionRouter(
            profiles: SandboxProfileStore(persistence: InMemoryPersistenceStore()),
            backends: [:])
        let tool = RunTerminalTool(actionHub: hub, router: router)
        let r = try await tool.execute(.object(["command": .string("echo should-not-run")]))
        #expect(r.isError)
        // The command text is echoed back verbatim in the "$ <command>" line
        // regardless of outcome, so assert on the absence of an actual exit
        // marker (proof nothing executed) and the presence of the blocked
        // marker instead of asserting the command string is entirely absent.
        #expect(r.content.contains("[blocked:"))
        #expect(!r.content.contains("[exit"))
    }
}
