// Tests/AinkradTests/ScriptedBatchToolTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("ScriptedBatchTool")
@MainActor
struct ScriptedBatchToolTests {
    @Test func disabledWhenNoSandbox() async throws {
        let tool = ScriptedBatchTool(executionRouter: nil)
        let r = try await tool.execute(.object(["script": .string("echo hi")]))
        #expect(r.isError)
        #expect(r.content.contains("no sandbox"))
    }

    @Test func permissionIsWriteAndIrreversible() {
        let tool = ScriptedBatchTool(executionRouter: nil)
        #expect(tool.permission == .write)
        #expect(tool.isIrreversible(.object(["script": .string("x")])))
    }

    @Test func rejectsEmptyScript() async {
        let tool = ScriptedBatchTool(executionRouter: nil)
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(.object(["script": .string("")]))
        }
    }

    @Test func rejectsMissingScript() async {
        let tool = ScriptedBatchTool(executionRouter: nil)
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(.object([:]))
        }
    }
}
