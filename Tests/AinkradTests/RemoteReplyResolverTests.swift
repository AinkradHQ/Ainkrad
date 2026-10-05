import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@MainActor
@Suite("RemoteReplyResolver")
struct RemoteReplyResolverTests {
    final class Noop: AgentRunRunner {
        func execute(prompt: String, posture: SavedExecutionPosture?, appendLog: @escaping (String) -> Void) async
            -> AgentRunOutcome
        { .success("") }
    }

    @Test func parsesResultPathButLeavesHookAlone() {
        #expect(WebhookServer.parseResultLookup("GET /result/ABC HTTP/1.1\r\n\r\n") == "ABC")
        #expect(WebhookServer.parseResultLookup("POST /hook/ABC HTTP/1.1\r\n\r\n") == nil)
        // existing POST parser still works and still rejects GET /hook
        #expect(WebhookServer.parse("POST /hook/ABC HTTP/1.1\r\nAuthorization: Bearer t\r\n\r\nx")?.endpointID == "ABC")
        #expect(WebhookServer.parse("GET /hook/ABC HTTP/1.1\r\n\r\n") == nil)
    }

    @Test func bodyReflectsRunStatus() {
        let runs = RunManager(persistence: InMemoryPersistenceStore(), runner: Noop())
        let run = runs.enqueue(prompt: "hi", origin: .event)
        #expect(
            RemoteReplyResolver.body(forRunID: run.id.uuidString, in: runs).contains("queued")
                || RemoteReplyResolver.body(forRunID: run.id.uuidString, in: runs).contains("running"))
        #expect(RemoteReplyResolver.body(forRunID: "not-a-run", in: runs).contains("unknown"))
    }

    @Test func getResultRequiresTheBearerToken() {
        // The reply endpoint is gated by the same token as POST /hook.
        #expect(
            WebhookServer.bearer(in: "GET /result/ABC HTTP/1.1\r\nAuthorization: Bearer secret\r\n\r\n") == "secret")
        #expect(WebhookServer.bearer(in: "GET /result/ABC HTTP/1.1\r\n\r\n") == nil)
        #expect(WebhookRequestValidator.isAuthorized(bearer: "secret", token: "secret"))
        #expect(!WebhookRequestValidator.isAuthorized(bearer: "wrong", token: "secret"))
        #expect(!WebhookRequestValidator.isAuthorized(bearer: nil, token: "secret"))
        #expect(!WebhookRequestValidator.isAuthorized(bearer: "secret", token: ""))
    }

    @Test func bodyIsAlwaysValidJSON() {
        // The reply is serialized via JSONSerialization, so results containing
        // quotes/backslashes/newlines (routine in terminal output) stay valid JSON.
        let runs = RunManager(persistence: InMemoryPersistenceStore(), runner: Noop())
        let run = runs.enqueue(prompt: "hi", origin: .event)
        for id in [run.id.uuidString, "not-a-run"] {
            let body = RemoteReplyResolver.body(forRunID: id, in: runs)
            let object = try? JSONSerialization.jsonObject(with: Data(body.utf8))
            #expect(object is [String: Any])  // parses as a JSON object
        }
    }
}
