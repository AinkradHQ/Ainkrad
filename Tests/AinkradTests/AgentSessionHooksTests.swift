import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("AgentSession tool hooks", .timeLimit(.minutes(1)))
@MainActor
struct AgentSessionHooksTests {
    private func hostRouter() -> ExecutionRouter {
        ExecutionRouter(
            profiles: SandboxProfileStore(persistence: InMemoryPersistenceStore()),
            backends: [.host: HostBackend()])
    }
    private func obj(_ d: [String: JSONValue]) -> JSONValue { .object(d) }

    @Test func preHookBlockPreventsTheToolFromRunning() async {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("h-\(UUID().uuidString).txt").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = ToolHooksStore(persistence: InMemoryPersistenceStore())
        store.add(
            ToolHook(
                id: UUID(), enabled: true, event: .preToolUse, match: "edit_file",
                command: "exit 1", timeoutSeconds: 10))
        let runner = ToolHookRunner(store: store, router: hostRouter(), workingDir: { NSHomeDirectory() })
        let session = TestSessionFactory.makeWithHooks(hooks: runner)

        // Real EditFileTool creating a new file — if the hook blocks, the file must NOT be created.
        let result = await session.executeForTesting(
            ToolCall(
                id: "1", name: "edit_file",
                input: obj(["path": .string(path), "old_string": .string(""), "new_string": .string("hi")])))
        #expect(result.isError)
        #expect(result.content.contains("Blocked by PreToolUse hook"))
        #expect(!FileManager.default.fileExists(atPath: path))
    }
}
