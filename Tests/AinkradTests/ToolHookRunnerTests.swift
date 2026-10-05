import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("ToolHookRunner", .timeLimit(.minutes(1)))
@MainActor
struct ToolHookRunnerTests {
    private func hostRouter() -> ExecutionRouter {
        ExecutionRouter(
            profiles: SandboxProfileStore(persistence: InMemoryPersistenceStore()),
            backends: [.host: HostBackend()])
    }
    private func obj(_ d: [String: JSONValue]) -> JSONValue { .object(d) }

    @Test func preHookNonZeroExitBlocksTheCall() async {
        let store = ToolHooksStore(persistence: InMemoryPersistenceStore())
        store.add(
            ToolHook(
                id: UUID(), enabled: true, event: .preToolUse, match: "run_terminal",
                command: "echo denied-by-policy 1>&2; exit 3", timeoutSeconds: 10))
        let runner = ToolHookRunner(store: store, router: hostRouter(), workingDir: { NSHomeDirectory() })
        let blocked = await runner.runPreToolUse(
            ToolCall(id: "1", name: "run_terminal", input: obj(["command": .string("ls")])))
        #expect(blocked != nil)
        #expect(blocked?.isError == true)
        #expect(blocked?.content.contains("denied-by-policy") == true)
    }

    @Test func preHookZeroExitAllowsTheCall() async {
        let store = ToolHooksStore(persistence: InMemoryPersistenceStore())
        store.add(
            ToolHook(
                id: UUID(), enabled: true, event: .preToolUse, match: "*",
                command: "exit 0", timeoutSeconds: 10))
        let runner = ToolHookRunner(store: store, router: hostRouter(), workingDir: { NSHomeDirectory() })
        let blocked = await runner.runPreToolUse(
            ToolCall(id: "1", name: "edit_file", input: obj(["path": .string("/tmp/x")])))
        #expect(blocked == nil)
    }

    @Test func noMatchingHookIsANoOp() async {
        let store = ToolHooksStore(persistence: InMemoryPersistenceStore())
        let runner = ToolHookRunner(store: store, router: hostRouter(), workingDir: { NSHomeDirectory() })
        #expect(await runner.runPreToolUse(ToolCall(id: "1", name: "edit_file", input: .object([:]))) == nil)
        let r = ToolResult(content: "edited", isError: false)
        let after = await runner.runPostToolUse(ToolCall(id: "1", name: "edit_file", input: .object([:])), result: r)
        #expect(after == r)  // unchanged
    }

    @Test func postHookOutputIsAppendedAsANote() async {
        let store = ToolHooksStore(persistence: InMemoryPersistenceStore())
        store.add(
            ToolHook(
                id: UUID(), enabled: true, event: .postToolUse, match: "edit_file",
                command: "echo formatted-ok", timeoutSeconds: 10))
        let runner = ToolHookRunner(store: store, router: hostRouter(), workingDir: { NSHomeDirectory() })
        let after = await runner.runPostToolUse(
            ToolCall(id: "1", name: "edit_file", input: .object([:])),
            result: ToolResult(content: "Edited /tmp/x.", isError: false))
        #expect(after.content.contains("Edited /tmp/x."))
        #expect(after.content.contains("formatted-ok"))
    }

    @Test func maliciousPathInputIsShellQuotedNotExecuted() async {
        let store = ToolHooksStore(persistence: InMemoryPersistenceStore())
        let marker = "/tmp/pwned-\(UUID().uuidString).txt"
        store.add(
            ToolHook(
                id: UUID(), enabled: true, event: .preToolUse, match: "*",
                command: "exit 0", timeoutSeconds: 10))
        let runner = ToolHookRunner(store: store, router: hostRouter(), workingDir: { NSHomeDirectory() })
        let maliciousPath = "'; touch \(marker); '"
        _ = await runner.runPreToolUse(
            ToolCall(id: "1", name: "edit_file", input: obj(["path": .string(maliciousPath)])))
        #expect(FileManager.default.fileExists(atPath: marker) == false)
    }
}
