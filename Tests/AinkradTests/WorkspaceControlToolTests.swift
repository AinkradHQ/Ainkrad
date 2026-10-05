import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@MainActor
@Suite("WorkspaceControlTool")
struct WorkspaceControlToolTests {
    private func obj(_ d: [String: JSONValue]) -> JSONValue { .object(d) }

    @Test("createWorkspace adds a workspace and returns success")
    func createWorkspace() async throws {
        let wm = WorkspaceManager()
        let tool = WorkspaceControlTool(workspaces: wm)
        let before = wm.workspaces.count
        let result = try await tool.execute(obj(["action": .string("createWorkspace")]))
        #expect(!result.isError)
        #expect(wm.workspaces.count == before + 1)
    }

    @Test("switchToWorkspace by index changes the active workspace")
    func switchByIndex() async throws {
        let wm = WorkspaceManager()
        _ = wm.createWorkspace()  // index 1 exists now
        let tool = WorkspaceControlTool(workspaces: wm)
        _ = try await tool.execute(
            obj([
                "action": .string("switchToWorkspace"),
                "index": .number(0),
            ]))
        #expect(wm.activeWorkspaceID == wm.workspaces[0].id)
    }

    @Test("deleteWorkspace removes a non-main workspace")
    func deleteWorkspace() async throws {
        let wm = WorkspaceManager()
        let created = wm.createWorkspace()
        let tool = WorkspaceControlTool(workspaces: wm)
        _ = try await tool.execute(
            obj([
                "action": .string("deleteWorkspace"),
                "id": .string(created.id.uuidString),
            ]))
        #expect(!wm.workspaces.contains { $0.id == created.id })
    }

    @Test("deleteWorkspace is flagged irreversible; others are not")
    func irreversibility() {
        let tool = WorkspaceControlTool(workspaces: WorkspaceManager())
        #expect(tool.isIrreversible(obj(["action": .string("deleteWorkspace"), "id": .string("x")])))
        #expect(!tool.isIrreversible(obj(["action": .string("createWorkspace")])))
    }

    @Test("unknown action returns an error result")
    func unknownAction() async throws {
        let tool = WorkspaceControlTool(workspaces: WorkspaceManager())
        let result = try await tool.execute(obj(["action": .string("nope")]))
        #expect(result.isError)
    }

    /// Builds a hub whose availability answers come from a fixed table and that
    /// records every open request, so `openApp` can be checked without a host.
    private func hub(
        _ availability: @escaping (String) -> PluginLaunchHub.Availability,
        opened: @escaping (String) -> Void
    ) -> PluginLaunchHub {
        let hub = PluginLaunchHub()
        hub.setAvailabilityProvider(availability)
        hub.setOpenHandler(opened)
        return hub
    }

    /// MCP tool calls no longer force an app open, so `openApp` is the only way
    /// the assistant can honour "open Lore".
    @Test("openApp requests an open for an available app")
    func openAppRequestsOpen() async throws {
        final class Box { var ids: [String] = [] }
        let box = Box()
        let launchHub = hub({ _ in .available }, opened: { box.ids.append($0) })
        let tool = WorkspaceControlTool(workspaces: WorkspaceManager(), launchHub: launchHub)
        let result = try await tool.execute(
            obj([
                "action": .string("openApp"),
                "appID": .string("lore"),
            ]))
        #expect(!result.isError)
        #expect(box.ids == ["lore"])
    }

    @Test("openApp reports an unknown app instead of silently doing nothing")
    func openAppUnknown() async throws {
        final class Box { var ids: [String] = [] }
        let box = Box()
        let launchHub = hub({ _ in .unknown }, opened: { box.ids.append($0) })
        let tool = WorkspaceControlTool(workspaces: WorkspaceManager(), launchHub: launchHub)
        let result = try await tool.execute(
            obj([
                "action": .string("openApp"),
                "appID": .string("ghost"),
            ]))
        #expect(result.isError)
        #expect(result.content.contains("installed"))
        #expect(box.ids.isEmpty)
    }

    /// Distinct from the unknown case: "disabled" is actionable by the user.
    @Test("openApp reports a disabled app distinctly")
    func openAppDisabled() async throws {
        final class Box { var ids: [String] = [] }
        let box = Box()
        let launchHub = hub({ _ in .disabled }, opened: { box.ids.append($0) })
        let tool = WorkspaceControlTool(workspaces: WorkspaceManager(), launchHub: launchHub)
        let result = try await tool.execute(
            obj([
                "action": .string("openApp"),
                "appID": .string("lore"),
            ]))
        #expect(result.isError)
        #expect(result.content.contains("disabled"))
        #expect(box.ids.isEmpty)
    }

    @Test("openApp without an appID is rejected")
    func openAppMissingAppID() async {
        // Held in a local: `launchHub` is weak, so an inline temporary would be
        // deallocated before `execute` ever looked at it.
        let launchHub = hub({ _ in .available }, opened: { _ in })
        let tool = WorkspaceControlTool(workspaces: WorkspaceManager(), launchHub: launchHub)
        await #expect(throws: ToolError.self) {
            try await tool.execute(obj(["action": .string("openApp")]))
        }
    }

    @Test("openApp is not irreversible")
    func openAppIsReversible() {
        let tool = WorkspaceControlTool(workspaces: WorkspaceManager())
        #expect(!tool.isIrreversible(obj(["action": .string("openApp"), "appID": .string("lore")])))
    }

    @Test("switchToWorkspace rejects non-finite, out-of-range, and fractional indices without crashing")
    func switchByIndexRejectsInvalidValues() async throws {
        let wm = WorkspaceManager()
        let tool = WorkspaceControlTool(workspaces: wm)

        let infResult = try await tool.execute(
            obj([
                "action": .string("switchToWorkspace"),
                "index": .number(Double.infinity),
            ]))
        #expect(infResult.isError)

        let nanResult = try await tool.execute(
            obj([
                "action": .string("switchToWorkspace"),
                "index": .number(Double.nan),
            ]))
        #expect(nanResult.isError)

        let hugeResult = try await tool.execute(
            obj([
                "action": .string("switchToWorkspace"),
                "index": .number(1e30),
            ]))
        #expect(hugeResult.isError)

        let fractionalResult = try await tool.execute(
            obj([
                "action": .string("switchToWorkspace"),
                "index": .number(2.5),
            ]))
        #expect(fractionalResult.isError)

        let negativeResult = try await tool.execute(
            obj([
                "action": .string("switchToWorkspace"),
                "index": .number(-1),
            ]))
        #expect(negativeResult.isError)
    }
}
