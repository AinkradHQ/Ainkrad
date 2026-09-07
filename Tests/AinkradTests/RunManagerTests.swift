import Foundation
import Testing
import AinkradSignal
@testable import Ainkrad
import AinkradHostRuntime

@Suite("RunManager", .timeLimit(.minutes(1)))
@MainActor
struct RunManagerTests {
    /// Completes immediately with a fixed result.
    final class InstantRunner: AgentRunRunner {
        func execute(prompt: String, posture: SavedExecutionPosture?, appendLog: @escaping (String) -> Void) async -> AgentRunOutcome {
            appendLog("ran \(prompt)")
            return .success("result:\(prompt)")
        }
    }

    /// M7 Wave B (B1) — records the `posture` each `execute` call actually
    /// received, so a test can prove it travelled end-to-end from
    /// `RunManager.enqueue(posture:)` through to the runner unchanged.
    final class RecordingPostureRunner: AgentRunRunner {
        private(set) var receivedPostures: [SavedExecutionPosture?] = []
        func execute(prompt: String, posture: SavedExecutionPosture?,
                     appendLog: @escaping (String) -> Void) async -> AgentRunOutcome {
            receivedPostures.append(posture)
            return .success("ok")
        }
    }

    /// Suspends until `release()` so concurrency can be observed mid-flight.
    final class GatedRunner: AgentRunRunner {
        private(set) var started = 0
        private var conts: [CheckedContinuation<Void, Never>] = []
        func execute(prompt: String, posture: SavedExecutionPosture?, appendLog: @escaping (String) -> Void) async -> AgentRunOutcome {
            started += 1
            await withCheckedContinuation { conts.append($0) }
            return .success("done")
        }
        func releaseAll() { conts.forEach { $0.resume() }; conts.removeAll() }
    }

    /// The notification half of this test used `RecordingRunNotifier`, which is
    /// gone with the notifier it doubled. The behaviour it protected — a
    /// completed run is *observable*, not silent — is preserved by asserting the
    /// feed recorded it.
    @Test func runCompletesPersistsAndNotifies() async throws {
        let p = InMemoryPersistenceStore()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("signal-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let center = SignalCenter(store: try SignalStore(url: url),
                                  deliverer: nil,
                                  contextProvider: RunManagerTestsContext())

        let mgr = RunManager(persistence: p, runner: InstantRunner(), signalCenter: center)
        let run = mgr.enqueue(prompt: "task-a")
        // Let the run task settle.
        await Task.yield(); await Task.yield()
        try? await Task.sleep(nanoseconds: 20_000_000)
        let reloaded = RunManager(persistence: p, runner: InstantRunner())
        let stored = reloaded.runs.first { $0.id == run.id }
        #expect(stored?.status == .done)
        #expect(stored?.result == "result:task-a")
        #expect(center.recent.contains { $0.kind == "run.finished" })
    }

    @Test func relaunchMarksRunningAsInterrupted() {
        let p = InMemoryPersistenceStore()
        var doc = AgentRunsDocument()
        doc.runs = [AgentRun(prompt: "crashed", status: .running)]
        p.save(doc)
        let mgr = RunManager(persistence: p, runner: InstantRunner())
        #expect(mgr.runs.first?.status == .interrupted)
    }

    @Test func concurrencyCapBoundsRunning() async {
        let runner = GatedRunner()
        let mgr = RunManager(persistence: InMemoryPersistenceStore(), runner: runner, maxConcurrent: 2)
        mgr.enqueue(prompt: "1"); mgr.enqueue(prompt: "2"); mgr.enqueue(prompt: "3")
        await Task.yield(); await Task.yield()
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(runner.started == 2)                                   // third is still queued
        #expect(mgr.runs.filter { $0.status == .running }.count == 2)
        runner.releaseAll()
    }

    @Test func pauseKeepsAQueuedRunFromStarting() async {
        let runner = GatedRunner()
        let mgr = RunManager(persistence: InMemoryPersistenceStore(), runner: runner, maxConcurrent: 1)
        let a = mgr.enqueue(prompt: "a")
        let b = mgr.enqueue(prompt: "b")
        mgr.pause(b.id)
        await Task.yield(); try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(mgr.runs.first { $0.id == b.id }?.status == .paused)
        #expect(runner.started == 1)                                   // only `a`
        runner.releaseAll()
        _ = a
    }

    @Test func stopFreesASlotForTheNextQueuedRun() async {
        let runner = GatedRunner()
        let mgr = RunManager(persistence: InMemoryPersistenceStore(), runner: runner, maxConcurrent: 1)
        let a = mgr.enqueue(prompt: "a")
        let b = mgr.enqueue(prompt: "b")
        await Task.yield(); try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(mgr.runs.first { $0.id == a.id }?.status == .running)
        mgr.stop(a.id)
        await Task.yield(); try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(mgr.runs.first { $0.id == a.id }?.status == .interrupted)
        #expect(mgr.runs.first { $0.id == b.id }?.status == .running)  // slot freed, next started
        #expect(mgr.runs.filter { $0.status == .running }.count == 1)  // cap never exceeded
        runner.releaseAll()
    }

    /// M7 Wave B (B1) — `enqueue(posture:)`'s posture reaches the runner
    /// unchanged, and is stored on the persisted `AgentRun`. A plain `enqueue`
    /// (no posture, the pre-Wave-B default) still passes `nil` through — the
    /// seam is additive and byte-identical for every pre-existing caller.
    @Test func enqueuePostureReachesTheRunner() async {
        let runner = RecordingPostureRunner()
        let mgr = RunManager(persistence: InMemoryPersistenceStore(), runner: runner)
        let posture = SavedExecutionPosture(permissionMode: "ask", sandboxProfileID: "workspace-write")
        let run = mgr.enqueue(prompt: "scheduled task", origin: .schedule, posture: posture)
        #expect(mgr.runs.first { $0.id == run.id }?.posture == posture)
        _ = mgr.enqueue(prompt: "chat task")   // no posture — pre-existing default
        await Task.yield(); await Task.yield()
        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(runner.receivedPostures.contains(posture))
        #expect(runner.receivedPostures.contains(nil))
    }
}

/// Present-and-looking context, so a completed run's routing is deterministic.
private struct RunManagerTestsContext: SignalContextProviding {
    var deliveryContext = DeliveryContext(hostIsFrontmost: true, visibleAppIDs: [],
                                          systemDoNotDisturb: false, hostFocusMode: false)
}
