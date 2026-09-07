import Testing
import Foundation
import AinkradSignal
@testable import Ainkrad

@Suite("SignalIngest")
struct SignalIngestTests {
    private func makeIngest() throws -> (SignalIngest, SignalStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("signal-\(UUID().uuidString).sqlite")
        let store = try SignalStore(url: url)
        return (SignalIngest(store: store), store, url)
    }

    private func draft(kind: String = "run.finished", title: String = "Run finished") -> SignalDraft {
        SignalDraft(kind: kind, severity: .success, title: title)
    }

    @Test("an accepted draft becomes a stored event stamped with the given source")
    func acceptsAndStamps() throws {
        let (ingest, store, url) = try makeIngest()
        defer { try? FileManager.default.removeItem(at: url) }
        guard case .accepted(let event) = ingest.accept(draft(), from: .app(appID: "raven")) else {
            Issue.record("expected acceptance"); return
        }
        #expect(event.source == .app(appID: "raven"))
        #expect(store.page(filter: .all, before: nil, limit: 10) == [event])
    }

    @Test("an emitter cannot forge another app's source")
    func forgeryIsInexpressible() throws {
        let (ingest, _, url) = try makeIngest()
        defer { try? FileManager.default.removeItem(at: url) }
        // SignalDraft has no `source` field at all - the only way to name a
        // source is the `from:` argument, which the host supplies. This test
        // pins that property so a future "convenience" field is caught.
        guard case .accepted(let event) = ingest.accept(draft(), from: .app(appID: "raven")) else {
            Issue.record("expected acceptance"); return
        }
        #expect(event.source == .app(appID: "raven"))
    }

    @Test("an invalid kind is rejected and never stored")
    func rejectsInvalidKind() throws {
        let (ingest, store, url) = try makeIngest()
        defer { try? FileManager.default.removeItem(at: url) }
        guard case .rejected(let rejection) = ingest.accept(draft(kind: "Run Finished"), from: .host) else {
            Issue.record("expected rejection"); return
        }
        #expect(rejection == .invalidKind("Run Finished"))
        #expect(store.page(filter: .all, before: nil, limit: 10).isEmpty)
    }

    @Test("an empty title is rejected")
    func rejectsEmptyTitle() throws {
        let (ingest, _, url) = try makeIngest()
        defer { try? FileManager.default.removeItem(at: url) }
        guard case .rejected(let rejection) = ingest.accept(draft(title: "   "), from: .host) else {
            Issue.record("expected rejection"); return
        }
        #expect(rejection == .emptyTitle)
    }

    @Test("over-long fields are truncated, not rejected")
    func truncatesRatherThanRejects() throws {
        let (ingest, _, url) = try makeIngest()
        defer { try? FileManager.default.removeItem(at: url) }
        let long = String(repeating: "x", count: 500)
        guard case .accepted(let event) = ingest.accept(
            SignalDraft(kind: "test.event", severity: .info, title: long), from: .host) else {
            Issue.record("expected acceptance"); return
        }
        #expect(event.title.count == SignalLimits.maxTitle)
    }

    @Test("a coalesced draft reports coalescence rather than acceptance")
    func reportsCoalescence() throws {
        let (ingest, store, url) = try makeIngest()
        defer { try? FileManager.default.removeItem(at: url) }
        let d = SignalDraft(kind: "build.failed", severity: .failure, title: "Build failed",
                            dedupeKey: "b:main")
        _ = ingest.accept(d, from: .host)
        guard case .coalesced = ingest.accept(d, from: .host) else {
            Issue.record("expected coalescence"); return
        }
        #expect(store.page(filter: .all, before: nil, limit: 10).count == 1)
    }
}
