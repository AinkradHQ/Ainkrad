import Foundation
import Testing

@testable import Ainkrad

@Suite("SubagentCoordinator", .timeLimit(.minutes(1)))
@MainActor
struct SubagentCoordinatorTests {
    // PROVISIONAL: `ModelTier` (.local) is from Slice 5. Confirm at execution.
    private func spec(_ prompt: String) -> SubagentSpec {
        SubagentSpec(id: UUID(), prompt: prompt, profileID: nil, toolAllowList: [], budgetTier: .local)
    }

    /// Echoes the prompt; `failOn` prompts return `.failed`.
    final class EchoRunner: SubagentRunner {
        let failOn: Set<String>
        init(failOn: Set<String> = []) { self.failOn = failOn }
        func run(_ spec: SubagentSpec) async -> SubagentOutcome {
            if failOn.contains(spec.prompt) {
                return SubagentOutcome(id: spec.id, status: .failed, resultText: "boom")
            }
            return SubagentOutcome(id: spec.id, status: .succeeded, resultText: "echo:\(spec.prompt)")
        }
    }

    /// Tracks the peak number of concurrently in-flight run() calls.
    final class PeakRunner: SubagentRunner {
        private(set) var inFlight = 0
        private(set) var peak = 0
        private var conts: [CheckedContinuation<Void, Never>] = []
        func run(_ spec: SubagentSpec) async -> SubagentOutcome {
            inFlight += 1
            peak = max(peak, inFlight)
            await withCheckedContinuation { conts.append($0) }
            inFlight -= 1
            return SubagentOutcome(id: spec.id, status: .succeeded, resultText: "ok")
        }
        func releaseAll() {
            conts.forEach { $0.resume() }
            conts.removeAll()
        }
    }

    @Test func aggregatesInInputOrder() async {
        let c = SubagentCoordinator(runner: EchoRunner())
        let out = await c.spawn([spec("a"), spec("b"), spec("c")])
        #expect(out.map(\.resultText) == ["echo:a", "echo:b", "echo:c"])
    }

    @Test func failureIsIsolated() async {
        let c = SubagentCoordinator(runner: EchoRunner(failOn: ["b"]))
        let out = await c.spawn([spec("a"), spec("b"), spec("c")])
        #expect(out[0].status == .succeeded)
        #expect(out[1].status == .failed)
        #expect(out[2].status == .succeeded)
    }

    @Test func respectsConcurrencyCap() async {
        let runner = PeakRunner()
        let c = SubagentCoordinator(runner: runner, maxConcurrent: 2)
        let task = Task { await c.spawn((0..<5).map { spec("t\($0)") }) }
        await Task.yield()
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(runner.peak <= 2)
        // 5 specs over a cap of 2 need multiple release waves: each
        // `releaseAll()` only resumes continuations already in flight, and
        // the next windowed batch appends fresh ones only after that. Drain
        // in waves (with a yield between) until every spec has completed.
        for _ in 0..<5 {
            runner.releaseAll()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        _ = await task.value
        #expect(runner.peak <= 2)
    }
}
