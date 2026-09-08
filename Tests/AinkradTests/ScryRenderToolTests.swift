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

@Suite("scry_render contract")
@MainActor
struct ScryRenderContractTests {
    private func properties() -> [String: JSONValue] {
        let tool = ScryRenderTool(store: ScryStore())
        guard case .object(let schema) = tool.parametersSchema,
              case .object(let props)? = schema["properties"] else { return [:] }
        return props
    }

    @Test("the schema exposes no pixel geometry")
    func noGeometry() {
        let p = properties()
        for banned in ["x", "y", "width", "height", "z"] {
            #expect(p[banned] == nil, "schema still exposes \(banned)")
        }
    }

    @Test("the schema exposes a size hint enumerating every case")
    func sizeExposed() {
        guard case .object(let size)? = properties()["size"] else {
            Issue.record("no size property"); return
        }
        guard case .array(let cases)? = size["enum"] else {
            Issue.record("size has no enum"); return
        }
        let raws = cases.compactMap(\.stringValue)
        #expect(Set(raws) == Set(ScrySizeHint.allCases.map(\.rawValue)))
    }

    @Test("the description tells the agent about size, not coordinates")
    func descriptionMentionsSize() {
        let d = ScryRenderTool(store: ScryStore()).description
        #expect(d.contains("size"))
        #expect(!d.contains("x/y"))
    }

    @Test("a size in the payload reaches the stored element")
    func sizeRoundTrips() async throws {
        let store = ScryStore()
        let registry = AgentToolRegistry(tools: [ScryRenderTool(store: store)])
        let result = await registry.run(ToolCall(
            id: "1", name: "scry_render",
            input: .object(["op": .string("add"), "kind": .string("text"),
                            "body": .string("hi"), "size": .string("full")])))
        #expect(!result.isError)
        #expect(store.model.elements.first?.sizeHint == .full)
    }
}
