import Foundation
import Testing
@testable import Ainkrad
import AinkradHostRuntime

@Suite("ScryRenderTool")
@MainActor
struct ScryRenderToolTests {
    private func make() -> (ScryRenderTool, ScryStore) {
        let store = ScryStore(sessionID: "s")
        return (ScryRenderTool(store: store), store)
    }

    @Test func addCreatesElement() async throws {
        let (tool, store) = make()
        let r = try await tool.execute(.object([
            "op": .string("add"), "id": .string("t1"),
            "kind": .string("table"), "body": .string("h|—\nr1")]))
        #expect(!r.isError)
        #expect(store.model.elements.first?.kind == .table)
    }

    @Test func updateMutatesInPlace() async throws {
        let (tool, store) = make()
        _ = try await tool.execute(.object(["op": .string("add"), "id": .string("t1"),
                                            "kind": .string("table"), "body": .string("r1")]))
        _ = try await tool.execute(.object(["op": .string("update"), "id": .string("t1"),
                                            "body": .string("r1\nr2")]))
        #expect(store.model.elements.first?.body == "r1\nr2")
    }

    @Test func removeDeletesElement() async throws {
        let (tool, store) = make()
        _ = try await tool.execute(.object(["op": .string("add"), "id": .string("a"),
                                            "kind": .string("text"), "body": .string("x")]))
        _ = try await tool.execute(.object(["op": .string("remove"), "id": .string("a")]))
        #expect(store.model.elements.isEmpty)
    }

    @Test func unknownKindIsIsolatedNotThrown() async throws {
        let (tool, store) = make()
        let r = try await tool.execute(.object(["op": .string("add"), "id": .string("h"),
                                                "kind": .string("hologram"), "body": .string("x")]))
        #expect(!r.isError)
        #expect(store.model.elements.first?.kind == .unknown)
    }

    @Test func removeWithoutIDThrows() async {
        let (tool, _) = make()
        await #expect(throws: ToolError.self) {
            _ = try await tool.execute(.object(["op": .string("remove")]))
        }
    }

    @Test func updateOnUnknownIDMaterializesElement() async throws {
        let (tool, store) = make()
        let input = JSONValue.object([
            "op": .string("update"), "id": .string("ghost"),
            "kind": .string("text"), "body": .string("materialized")])

        let r = try await tool.execute(input)
        #expect(!r.isError)

        // The element must actually exist in the store after the call returns.
        let live = store.model.elements.first(where: { $0.id == "ghost" })
        #expect(live?.body == "materialized")
        #expect(live?.kind == .text)
    }

    @Test func permissionIsReadAndReversible() {
        let (tool, _) = make()
        #expect(tool.permission == .read)
        #expect(tool.isIrreversible(.object([:])) == false)
    }
}
