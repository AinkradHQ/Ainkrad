import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("MCP wire types")
struct MCPWireTypesTests {
    @Test func buildsJSONRPCRequest() {
        let req = MCPRPC.request(id: "7", method: "tools/list", params: .object([:]))
        #expect(req["jsonrpc"]?.stringValue == "2.0")
        #expect(req["id"]?.stringValue == "7")
        #expect(req["method"]?.stringValue == "tools/list")
        #expect(req["params"] != nil)
    }

    @Test func notificationHasNoID() {
        let n = MCPRPC.notification(method: "notifications/initialized", params: .object([:]))
        #expect(n["method"]?.stringValue == "notifications/initialized")
        #expect(n["id"] == nil)
    }

    @Test func decodesSuccessResponse() {
        let msg = JSONValue.object([
            "jsonrpc": .string("2.0"), "id": .string("7"),
            "result": .object(["ok": .bool(true)]),
        ])
        guard case .success(let (id, result)) = MCPRPC.decodeResponse(msg) else {
            Issue.record("expected success")
            return
        }
        #expect(id == "7")
        #expect(result["ok"] != nil)
    }

    @Test func decodesRPCError() {
        let msg = JSONValue.object([
            "jsonrpc": .string("2.0"), "id": .string("9"),
            "error": .object(["code": .number(-32601), "message": .string("Method not found")]),
        ])
        guard case .failure(.rpc(let code, let message)) = MCPRPC.decodeResponse(msg) else {
            Issue.record("expected rpc error")
            return
        }
        #expect(code == -32601)
        #expect(message == "Method not found")
    }

    @Test func decodesRPCErrorWithOutOfRangeCodeDoesNotCrash() {
        let msg = JSONValue.object([
            "jsonrpc": .string("2.0"), "id": .string("9"),
            "error": .object(["code": .number(1e300), "message": .string("huge code")]),
        ])
        guard case .failure(.rpc(let code, let message)) = MCPRPC.decodeResponse(msg) else {
            Issue.record("expected rpc error")
            return
        }
        #expect(code == 0)
        #expect(message == "huge code")
    }

    @Test func decodesRPCErrorWithNaNCodeDoesNotCrash() {
        let msg = JSONValue.object([
            "jsonrpc": .string("2.0"), "id": .string("9"),
            "error": .object(["code": .number(.nan), "message": .string("nan code")]),
        ])
        guard case .failure(.rpc(let code, let message)) = MCPRPC.decodeResponse(msg) else {
            Issue.record("expected rpc error")
            return
        }
        #expect(code == 0)
        #expect(message == "nan code")
    }

    @Test func decodesToolList() {
        let result = JSONValue.object([
            "tools": .array([
                .object([
                    "name": .string("search"),
                    "description": .string("web search"),
                    "inputSchema": .object(["type": .string("object")]),
                ]),
                .object(["name": .string("fetch")]),  // missing desc/schema tolerated
            ])
        ])
        let tools = MCPRPC.decodeToolList(result)
        #expect(tools.count == 2)
        #expect(tools.first?.name == "search")
        #expect(tools.first?.description == "web search")
        #expect(tools.last?.description == "")
        // Finding 6: no annotations means "not destructive" — the host must not
        // invent a risk claim the server never made.
        #expect(tools.last?.destructive == false)
        #expect(tools.last?.readOnly == false)
    }

    @Test("tool annotations decode into the descriptor")
    func decodesToolAnnotations() {
        let result = JSONValue.object([
            "tools": .array([
                .object([
                    "name": .string("reset"),
                    "annotations": .object([
                        "destructiveHint": .bool(true),
                        "readOnlyHint": .bool(false),
                    ]),
                ]),
                .object([
                    "name": .string("status"),
                    "annotations": .object([
                        "destructiveHint": .bool(false),
                        "readOnlyHint": .bool(true),
                    ]),
                ]),
            ])
        ])
        let tools = MCPRPC.decodeToolList(result)
        #expect(tools.first?.destructive == true)
        #expect(tools.first?.readOnly == false)
        #expect(tools.last?.destructive == false)
        #expect(tools.last?.readOnly == true)
    }

    /// Ainkrad-namespaced, because it is not a standard MCP annotation. Absent
    /// must decode as `false`: a remote server never sends it, and the host must
    /// never pop an app window open on a claim no server made.
    @Test("ainkrad/requiresLiveApp decodes, and defaults to false when absent")
    func decodesRequiresLiveApp() {
        let result = JSONValue.object([
            "tools": .array([
                .object([
                    "name": .string("draw"),
                    "annotations": .object(["ainkrad/requiresLiveApp": .bool(true)]),
                ]),
                .object([
                    "name": .string("note"),
                    "annotations": .object(["ainkrad/requiresLiveApp": .bool(false)]),
                ]),
                .object(["name": .string("legacy")]),
            ])
        ])
        let tools = MCPRPC.decodeToolList(result)
        #expect(tools[0].requiresLiveApp == true)
        #expect(tools[1].requiresLiveApp == false)
        #expect(tools[2].requiresLiveApp == false)
    }

    @Test("resource annotations carry ainkrad/requiresLiveApp")
    func decodesResourceRequiresLiveApp() {
        let result = JSONValue.object([
            "resources": .array([
                .object([
                    "uri": .string("lore://live"),
                    "annotations": .object(["ainkrad/requiresLiveApp": .bool(true)]),
                ]),
                .object(["uri": .string("lore://cold")]),
            ])
        ])
        let resources = MCPRPC.decodeResourceList(result)
        #expect(resources[0].requiresLiveApp == true)
        #expect(resources[1].requiresLiveApp == false)
    }

    @Test("a resource's MCP description decodes, and its absence is an empty string")
    func decodesResourceDescription() {
        let result = JSONValue.object([
            "resources": .array([
                .object([
                    "uri": .string("lore://notes"),
                    "description": .string("Read when the user asks about the vault."),
                ]),
                // A remote server predating the field must not become nil-shaped:
                // the tool description branches on `isEmpty`, not on optionality.
                .object(["uri": .string("lore://plain")]),
            ])
        ])
        let resources = MCPRPC.decodeResourceList(result)
        #expect(resources[0].description == "Read when the user asks about the vault.")
        #expect(resources[1].description == "")
    }
}
