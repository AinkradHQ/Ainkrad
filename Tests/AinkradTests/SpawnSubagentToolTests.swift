import AinkradHostRuntime
// Tests/AinkradTests/SpawnSubagentToolTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("SpawnSubagentTool")
@MainActor
struct SpawnSubagentToolTests {
    final class EchoRunner: SubagentRunner {
        func run(_ spec: SubagentSpec) async -> SubagentOutcome {
            SubagentOutcome(id: spec.id, status: .succeeded, resultText: "echo:\(spec.prompt)")
        }
    }
    final class AllFailRunner: SubagentRunner {
        func run(_ spec: SubagentSpec) async -> SubagentOutcome {
            SubagentOutcome(id: spec.id, status: .failed, resultText: "nope")
        }
    }
    /// Records the specs it was asked to run so tests can assert on parsed shape.
    final class RecordingRunner: SubagentRunner {
        private(set) var seen: [SubagentSpec] = []
        func run(_ spec: SubagentSpec) async -> SubagentOutcome {
            seen.append(spec)
            return SubagentOutcome(id: spec.id, status: .succeeded, resultText: "ok")
        }
    }

    private func tool(_ runner: SubagentRunner, agents: AgentStore? = nil) -> SpawnSubagentTool {
        SpawnSubagentTool(
            coordinator: SubagentCoordinator(runner: runner),
            agents: agents ?? AgentStore(persistence: InMemoryPersistenceStore()))
    }

    @Test func permissionIsWrite() {
        #expect(tool(EchoRunner()).permission == .write)
    }

    @Test func fansOutTasksAndAggregates() async throws {
        let r = try await tool(EchoRunner()).execute(
            .object([
                "tasks": .array([
                    .object(["prompt": .string("audit deps")]),
                    .object(["prompt": .string("write tests"), "model_budget": .string("premium")]),
                ])
            ]))
        #expect(!r.isError)
        #expect(r.content.contains("echo:audit deps"))
        #expect(r.content.contains("echo:write tests"))
    }

    @Test func singlePromptFormNormalizes() async throws {
        let r = try await tool(EchoRunner()).execute(.object(["prompt": .string("one thing")]))
        #expect(r.content.contains("echo:one thing"))
    }

    @Test func allFailedIsError() async throws {
        let r = try await tool(AllFailRunner()).execute(.object(["prompt": .string("x")]))
        #expect(r.isError)
    }

    @Test func partialFailureIsNotError() async throws {
        final class MixedRunner: SubagentRunner {
            func run(_ spec: SubagentSpec) async -> SubagentOutcome {
                spec.prompt.contains("bad")
                    ? SubagentOutcome(id: spec.id, status: .failed, resultText: "boom")
                    : SubagentOutcome(id: spec.id, status: .succeeded, resultText: "good")
            }
        }
        let r = try await tool(MixedRunner()).execute(
            .object([
                "tasks": .array([
                    .object(["prompt": .string("good one")]),
                    .object(["prompt": .string("bad one")]),
                ])
            ]))
        #expect(!r.isError)
        #expect(r.content.contains("good"))
        #expect(r.content.contains("boom"))
    }

    @Test func rejectsEmptyTasks() async {
        await #expect(throws: ToolError.self) {
            _ = try await tool(EchoRunner()).execute(.object(["tasks": .array([])]))
        }
    }

    @Test func rejectsMissingPromptEverywhere() async {
        await #expect(throws: ToolError.self) {
            _ = try await tool(EchoRunner()).execute(.object([:]))
        }
    }

    @Test func rejectsTaskWithMissingPrompt() async {
        await #expect(throws: ToolError.self) {
            _ = try await tool(EchoRunner()).execute(
                .object([
                    "tasks": .array([.object(["agent": .string("Build")])])
                ]))
        }
    }

    @Test func rejectsTaskWithEmptyPrompt() async {
        await #expect(throws: ToolError.self) {
            _ = try await tool(EchoRunner()).execute(
                .object([
                    "tasks": .array([.object(["prompt": .string("")])])
                ]))
        }
    }

    @Test func rejectsMalformedTasksShape() async {
        // "tasks" present but not an array, and no top-level "prompt" fallback.
        await #expect(throws: ToolError.self) {
            _ = try await tool(EchoRunner()).execute(.object(["tasks": .string("nope")]))
        }
    }

    @Test func defaultBudgetIsCheapPaid() async throws {
        let runner = RecordingRunner()
        _ = try await tool(runner).execute(.object(["prompt": .string("x")]))
        #expect(runner.seen.first?.budgetTier == .cheapPaid)
    }

    @Test func parsesModelBudgetAndToolAllowList() async throws {
        let runner = RecordingRunner()
        _ = try await tool(runner).execute(
            .object([
                "tasks": .array([
                    .object([
                        "prompt": .string("scoped task"),
                        "model_budget": .string("local"),
                        "tools": .array([.string("read_file"), .string("run_terminal")]),
                    ])
                ])
            ]))
        #expect(runner.seen.first?.budgetTier == .local)
        #expect(runner.seen.first?.toolAllowList == ["read_file", "run_terminal"])
    }

    @Test func resolvesAgentNameToProfileID() async throws {
        let agents = AgentStore(persistence: InMemoryPersistenceStore())
        let profile = agents.add(
            AgentProfile(
                name: "Auditor", instructions: "audit",
                toolPolicy: .all))
        let runner = RecordingRunner()
        _ = try await tool(runner, agents: agents).execute(
            .object([
                "tasks": .array([.object(["prompt": .string("go"), "agent": .string("auditor")])])
            ]))
        #expect(runner.seen.first?.profileID == profile.id)
    }

    @Test func unknownAgentNameLeavesProfileIDNil() async throws {
        let runner = RecordingRunner()
        _ = try await tool(runner).execute(
            .object([
                "tasks": .array([.object(["prompt": .string("go"), "agent": .string("nonexistent")])])
            ]))
        #expect(runner.seen.first?.profileID == nil)
    }

    @Test func rejectsTooManyTasks() async {
        let manyTasks = (0..<(SpawnSubagentTool.maxTasksPerCall + 1)).map { i in
            JSONValue.object(["prompt": .string("task \(i)")])
        }
        await #expect(throws: ToolError.self) {
            _ = try await tool(EchoRunner()).execute(.object(["tasks": .array(manyTasks)]))
        }
    }

    @Test func acceptsExactlyTheCap() async throws {
        let tasks = (0..<SpawnSubagentTool.maxTasksPerCall).map { i in
            JSONValue.object(["prompt": .string("task \(i)")])
        }
        let r = try await tool(EchoRunner()).execute(.object(["tasks": .array(tasks)]))
        #expect(!r.isError)
    }
}
