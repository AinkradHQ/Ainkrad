import Testing
import Foundation
import AinkradSignal
import AinkradHostRuntime
@testable import Ainkrad

/// Exactly one banner per completed run, exercised through the REAL
/// `RunManager` completion path rather than by calling `SignalCenter.emit`.
///
/// In M1 `RunNotifier` owned this banner and a routing exemption kept Signal
/// from posting a second one. M2 deletes the notifier, so the banner must now
/// arrive through Signal — and the risk inverts: instead of two banners, the
/// failure mode is ZERO, silently.
@MainActor
@Suite("Exactly one banner per completed run")
final class RunBannerIntegrationTests {
    private final class InstantRunner: AgentRunRunner {
        func execute(prompt: String, posture: SavedExecutionPosture?,
                     appendLog: @escaping (String) -> Void) async -> AgentRunOutcome {
            .success("done")
        }
    }
    private final class FailingRunner: AgentRunRunner {
        func execute(prompt: String, posture: SavedExecutionPosture?,
                     appendLog: @escaping (String) -> Void) async -> AgentRunOutcome {
            .failure("exploded")
        }
    }
    private final class SpyDeliverer: SignalDeliverer {
        private(set) var delivered: [(SignalEvent, Set<DeliveryChannel>)] = []
        func deliver(_ event: SignalEvent, to channels: Set<DeliveryChannel>) {
            delivered.append((event, channels))
        }
    }
    /// The user has looked away — the situation in which a run banner matters,
    /// and the one where a duplicate would be most obvious.
    private struct AwayContext: SignalContextProviding {
        var deliveryContext = DeliveryContext(hostIsFrontmost: false, visibleAppIDs: [],
                                              systemDoNotDisturb: false, hostFocusMode: false)
    }

    private func waitForCompletion(_ manager: RunManager, id: UUID) async {
        for _ in 0..<200 {
            if let run = manager.runs.first(where: { $0.id == id }),
               run.status == .done || run.status == .failed || run.status == .interrupted {
                return
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("run did not finish within the timeout")
    }

    private func makeCenter(_ deliverer: SpyDeliverer) throws -> (SignalCenter, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("signal-\(UUID().uuidString).sqlite")
        return (SignalCenter(store: try SignalStore(url: url),
                             deliverer: deliverer, contextProvider: AwayContext()), url)
    }

    @Test("a successful run posts one legacy banner and zero Signal banners")
    func successfulRun() async throws {
        let deliverer = SpyDeliverer()
        let (center, url) = try makeCenter(deliverer)
        defer { try? FileManager.default.removeItem(at: url) }
        let manager = RunManager(persistence: InMemoryPersistenceStore(),
                                 runner: InstantRunner(),
                                 signalCenter: center)

        let run = manager.enqueue(prompt: "do the thing", origin: .chat)
        await waitForCompletion(manager, id: run.id)

        #expect(center.recent.count == 1)
        #expect(center.recent.first?.kind == "run.finished")
        #expect(deliverer.delivered.count == 1)
        let channels = deliverer.delivered[0].1
        #expect(channels.contains(.banner),
                "RunNotifier is gone; if Signal does not post it, the user gets nothing")
        #expect(channels.contains(.feed))
    }

    @Test("a failed run behaves the same way")
    func failedRun() async throws {
        let deliverer = SpyDeliverer()
        let (center, url) = try makeCenter(deliverer)
        defer { try? FileManager.default.removeItem(at: url) }
        let manager = RunManager(persistence: InMemoryPersistenceStore(),
                                 runner: FailingRunner(),
                                 signalCenter: center)

        let run = manager.enqueue(prompt: "break the thing", origin: .chat)
        await waitForCompletion(manager, id: run.id)

        #expect(center.recent.first?.kind == "run.failed")
        #expect(center.recent.first?.severity == .failure)
        #expect(deliverer.delivered[0].1.contains(.banner))
        #expect(deliverer.delivered[0].1.contains(.sound), "a failure still makes a sound")
    }

    @Test("two runs produce two feed rows and two banners, not four")
    func twoRuns() async throws {
        let deliverer = SpyDeliverer()
        let (center, url) = try makeCenter(deliverer)
        defer { try? FileManager.default.removeItem(at: url) }
        let manager = RunManager(persistence: InMemoryPersistenceStore(),
                                 runner: InstantRunner(),
                                 signalCenter: center)

        let first = manager.enqueue(prompt: "one", origin: .chat)
        let second = manager.enqueue(prompt: "two", origin: .chat)
        await waitForCompletion(manager, id: first.id)
        await waitForCompletion(manager, id: second.id)

        #expect(center.recent.count == 2, "distinct runs must not coalesce into one row")
        #expect(deliverer.delivered.count == 2)
        #expect(deliverer.delivered.allSatisfy { $0.1.contains(.banner) },
                "one banner per run, from Signal")
    }
}
