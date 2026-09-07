import Testing
import Foundation
import AinkradSignal
@testable import Ainkrad

@MainActor
@Suite("RunManager emits into Signal while RunNotifier still owns the banner")
final class RunManagerSignalTests {
    private final class SpyDeliverer: SignalDeliverer {
        var delivered: [(SignalEvent, Set<DeliveryChannel>)] = []
        func deliver(_ event: SignalEvent, to channels: Set<DeliveryChannel>) {
            delivered.append((event, channels))
        }
    }
    private struct AwayContext: SignalContextProviding {
        var deliveryContext = DeliveryContext(hostIsFrontmost: false, visibleAppIDs: [],
                                              systemDoNotDisturb: false, hostFocusMode: false)
    }

    @Test("a completed run produces exactly one feed event and one banner")
    func oneBannerPerRun() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("signal-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let deliverer = SpyDeliverer()
        let center = SignalCenter(store: try SignalStore(url: url),
                                  deliverer: deliverer, contextProvider: AwayContext())

        let run = AgentRun(id: UUID(), prompt: "do the thing", status: .done,
                           result: "did the thing")
        center.emit(.runCompleted(run), from: .host)

        #expect(center.recent.count == 1)
        #expect(center.recent[0].kind == "run.finished")
        #expect(center.recent[0].severity == .success)
        #expect(deliverer.delivered.count == 1)
        #expect(deliverer.delivered[0].1.contains(.banner),
                "Signal is the only banner path now; without it the run finishes silently")
    }

    @Test("a failed run maps to failure severity and run.failed")
    func failedRunMapping() {
        let run = AgentRun(id: UUID(), prompt: "do the thing", status: .failed,
                           result: "exploded")
        let draft = SignalDraft.runCompleted(run)
        #expect(draft.kind == "run.failed")
        #expect(draft.severity == .failure)
        #expect(draft.title == "Run failed")
        #expect(draft.body?.contains("do the thing") == true)
    }

    @Test("an interrupted run is a warning, not a failure")
    func interruptedRunMapping() {
        let run = AgentRun(id: UUID(), prompt: "p", status: .interrupted, result: nil)
        let draft = SignalDraft.runCompleted(run)
        #expect(draft.kind == "run.interrupted")
        #expect(draft.severity == .warning)
    }

    @Test("the dedupe key is the run id, so a retried delivery cannot double the feed")
    func dedupeKeyIsRunID() {
        let run = AgentRun(id: UUID(), prompt: "p", status: .done, result: nil)
        #expect(SignalDraft.runCompleted(run).dedupeKey == "run:\(run.id.uuidString)")
    }
}
