import Foundation
import Testing

@testable import Ainkrad

@Suite("AgentRun")
struct AgentRunTests {
    @Test func defaultsToQueuedChatRun() {
        let r = AgentRun(prompt: "do it")
        #expect(r.status == .queued)
        #expect(r.origin == .chat)
        #expect(r.logs.isEmpty)
        #expect(r.result == nil)
        #expect(r.startedAt == nil)
    }

    @Test func codableRoundTrips() throws {
        var r = AgentRun(origin: .schedule, prompt: "nightly")
        r.status = .done
        r.logs = ["started", "finished"]
        r.result = "ok"
        r.finishedAt = Date(timeIntervalSince1970: 100)
        let data = try JSONEncoder().encode(r)
        #expect(try JSONDecoder().decode(AgentRun.self, from: data) == r)
    }

    @Test func documentHoldsRuns() {
        var doc = AgentRunsDocument()
        doc.runs.append(AgentRun(prompt: "a"))
        #expect(doc.runs.count == 1)
        #expect(AgentRunsDocument.documentID == "agent-runs")
    }

    /// Forward-compat: a payload missing later fields decodes with defaults.
    @Test func decodesLegacyPayloadMissingFields() throws {
        let legacy = #"{"id":"\#(UUID().uuidString)","prompt":"old"}"#.data(using: .utf8)!
        let run = try JSONDecoder().decode(AgentRun.self, from: legacy)
        #expect(run.status == .queued)
        #expect(run.origin == .chat)
        #expect(run.logs.isEmpty)
        #expect(run.posture == nil)
    }

    /// M7 Wave B (B1c) — `AgentRun.posture` round-trips through encode/decode.
    @Test func postureRoundTrips() throws {
        var r = AgentRun(
            origin: .schedule, prompt: "nightly",
            posture: SavedExecutionPosture(permissionMode: "ask", sandboxProfileID: "workspace-write"))
        r.status = .done
        let data = try JSONEncoder().encode(r)
        let decoded = try JSONDecoder().decode(AgentRun.self, from: data)
        #expect(decoded == r)
        #expect(decoded.posture?.permissionMode == "ask")
        #expect(decoded.posture?.sandboxProfileID == "workspace-write")
    }

    /// M7 Wave B (B1c) — an old persisted payload predating the `posture` field
    /// (this file's own pre-Wave-B `codableRoundTrips` payload shape) still
    /// decodes, with `posture` falling back to `nil` rather than throwing.
    @Test func decodesPreWaveBPayloadWithoutPostureField() throws {
        let id = UUID().uuidString
        let legacy = #"{"id":"\#(id)","origin":"schedule","prompt":"nightly","status":"done","logs":[]}"#
            .data(using: .utf8)!
        let run = try JSONDecoder().decode(AgentRun.self, from: legacy)
        #expect(run.origin == .schedule)
        #expect(run.status == .done)
        #expect(run.posture == nil)
    }

    @Test func documentDecodesEmptyObject() throws {
        let doc = try JSONDecoder().decode(AgentRunsDocument.self, from: "{}".data(using: .utf8)!)
        #expect(doc.runs.isEmpty)
    }
}
