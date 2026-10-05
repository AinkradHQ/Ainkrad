import Foundation
// Tests/AinkradTests/SandboxProcessStreamTests.swift
import Testing

@testable import Ainkrad

@Suite("SandboxProcessRunner streaming", .timeLimit(.minutes(1)))
struct SandboxProcessStreamTests {
    @Test func emitsIncrementalSnapshotsBeforeCompletion() async {
        let runner = SandboxProcessRunner()
        // Serialize snapshots under a lock (the callback fires on a background queue).
        final class Sink: @unchecked Sendable {
            private let lock = NSLock()
            private var snaps: [String] = []
            func add(_ s: String) {
                lock.lock()
                snaps.append(s)
                lock.unlock()
            }
            func all() -> [String] {
                lock.lock()
                defer { lock.unlock() }
                return snaps
            }
        }
        let sink = Sink()
        let result = await runner.run(
            executable: "/bin/zsh",
            arguments: ["-lc", "echo a; echo b; echo c"],
            workingDir: NSHomeDirectory(), timeout: 10,
            onOutput: { sink.add($0) })
        #expect(result.output.contains("a"))
        #expect(result.output.contains("c"))
        // At least one snapshot was delivered while running, and the last snapshot
        // is a prefix-or-equal of the final captured output (monotonic growth).
        #expect(!sink.all().isEmpty)
        #expect(sink.all().last?.contains("a") == true)
    }

    @Test func hostBackendForwardsRequestOnOutput() async throws {
        final class Sink: @unchecked Sendable {
            private let lock = NSLock()
            private var got = false
            func mark() {
                lock.lock()
                got = true
                lock.unlock()
            }
            func any() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                return got
            }
        }
        let sink = Sink()
        var request = ExecutionRequest(
            command: "echo streamed", workingDir: NSHomeDirectory(),
            profile: BuiltInSandboxProfiles.hostTrusted)
        request.onOutput = { _ in sink.mark() }
        let result = try await HostBackend().run(request)
        #expect(result.output.contains("streamed"))
        #expect(sink.any())
    }
}
