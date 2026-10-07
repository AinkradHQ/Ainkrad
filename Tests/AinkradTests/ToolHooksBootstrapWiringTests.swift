import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("ToolHooks bootstrap wiring", .timeLimit(.minutes(1)))
@MainActor
struct ToolHooksBootstrapWiringTests {
    @Test func runnerConsultsTheLiveStore() async {
        let persistence = InMemoryPersistenceStore()
        let store = ToolHooksStore(persistence: persistence)
        store.add(
            ToolHook(
                id: UUID(), enabled: true, event: .preToolUse, match: "run_terminal",
                command: "exit 7", timeoutSeconds: 5))
        let router = ExecutionRouter(
            profiles: SandboxProfileStore(persistence: persistence), backends: [.host: HostBackend()])
        let runner = ToolHookRunner(store: store, router: router, workingDir: { NSHomeDirectory() })
        let blocked = await runner.runPreToolUse(
            ToolCall(id: "1", name: "run_terminal", input: .object(["command": .string("ls")])))
        #expect(blocked?.isError == true)
    }
}
