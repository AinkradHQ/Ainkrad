import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("WebhookRequestValidator")
struct WebhookServerTests {
    private let sid = UUID().uuidString

    @Test func acceptsValidBearerAndKnownEndpoint() {
        let r = WebhookRequestValidator.validate(
            WebhookRequest(endpointID: sid, bearer: "s3cret", body: "{\"ref\":\"main\"}"),
            token: "s3cret", knownEndpoints: [sid])
        guard case .success(let event) = r else {
            Issue.record("expected success")
            return
        }
        #expect(event.scheduleID.uuidString == sid)
        #expect(event.payload.contains("main"))
    }

    @Test func rejectsWrongToken() {
        let r = WebhookRequestValidator.validate(
            WebhookRequest(endpointID: sid, bearer: "nope", body: ""),
            token: "s3cret", knownEndpoints: [sid])
        #expect(r == .failure(.unauthorized))
    }

    @Test func rejectsMissingBearer() {
        let r = WebhookRequestValidator.validate(
            WebhookRequest(endpointID: sid, bearer: nil, body: ""),
            token: "s3cret", knownEndpoints: [sid])
        #expect(r == .failure(.unauthorized))
    }

    @Test func rejectsUnknownEndpoint() {
        let r = WebhookRequestValidator.validate(
            WebhookRequest(endpointID: "other", bearer: "s3cret", body: ""),
            token: "s3cret", knownEndpoints: [sid])
        #expect(r == .failure(.unknownEndpoint))
    }

    @Test func rejectsEmptyToken() {
        let r = WebhookRequestValidator.validate(
            WebhookRequest(endpointID: sid, bearer: "", body: ""),
            token: "", knownEndpoints: [sid])
        #expect(r == .failure(.unauthorized))
    }

    @Test func parsesValidHTTPRequest() {
        let raw = "POST /hook/\(sid) HTTP/1.1\r\nAuthorization: Bearer s3cret\r\n\r\n{\"ref\":\"main\"}"
        let parsed = WebhookServer.parse(raw)
        #expect(parsed?.endpointID == sid)
        #expect(parsed?.bearer == "s3cret")
        #expect(parsed?.body == "{\"ref\":\"main\"}")
    }

    @Test func parseRejectsNonPostMethod() {
        let raw = "GET /hook/\(sid) HTTP/1.1\r\nAuthorization: Bearer s3cret\r\n\r\n"
        #expect(WebhookServer.parse(raw) == nil)
    }

    @Test func parseRejectsMissingHookPath() {
        let raw = "POST /other/\(sid) HTTP/1.1\r\nAuthorization: Bearer s3cret\r\n\r\n"
        #expect(WebhookServer.parse(raw) == nil)
    }
}

@Suite("WebhookServer loopback acceptance", .tags(.integration))
@MainActor
struct WebhookServerAcceptanceTests {
    final class InstantRunner: AgentRunRunner {
        func execute(prompt: String, posture: SavedExecutionPosture?, appendLog: @escaping (String) -> Void) async
            -> AgentRunOutcome
        { .success("ok") }
    }

    @Test func authenticatedPostFiresTriggerAndReturns202() async throws {
        let store = ScheduleStore(persistence: InMemoryPersistenceStore())
        let runs = RunManager(persistence: InMemoryPersistenceStore(), runner: InstantRunner())
        let schedule = AgentSchedule(
            name: "webhook",
            trigger: .fileChange(path: "/repo", glob: "*.swift"),
            prompt: "run tests", posture: SavedExecutionPosture(permissionMode: "ask", sandboxProfileID: nil))
        store.upsert(schedule)
        let dispatcher = TriggerDispatcher(store: store, runs: runs, minInterval: 0)
        let server = WebhookServer(
            port: 0, token: "s3cret", dispatcher: dispatcher,
            schedulesProviding: { [schedule.id.uuidString] })
        try server.start()
        defer { server.stop() }

        var port: UInt16?
        for _ in 0..<50 {
            if let p = server.resolvedPort {
                port = p
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard let port else {
            Issue.record("listener never became ready")
            return
        }

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/hook/\(schedule.id.uuidString)")!)
        request.httpMethod = "POST"
        request.setValue("Bearer s3cret", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{\"ref\":\"main\"}".utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode
        #expect(status == 202)

        var unauthorized = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/hook/\(schedule.id.uuidString)")!)
        unauthorized.httpMethod = "POST"
        unauthorized.setValue("Bearer wrong", forHTTPHeaderField: "Authorization")
        unauthorized.httpBody = Data("{}".utf8)
        let (_, response2) = try await URLSession.shared.data(for: unauthorized)
        let status2 = (response2 as? HTTPURLResponse)?.statusCode
        #expect(status2 == 401)
    }
}

extension Tag {
    @Tag static var integration: Self
}
