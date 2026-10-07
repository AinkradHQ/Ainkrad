// Tests/AinkradTests/SandboxProcessRunnerTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("SandboxProcessRunner")
struct SandboxProcessRunnerTests {
    private let runner = SandboxProcessRunner()

    @Test func capturesStdoutAndExitZero() async {
        let r = await runner.run(
            executable: "/bin/echo", arguments: ["hi"],
            workingDir: nil, timeout: 10)
        #expect(r.output.contains("hi"))
        #expect(r.exitCode == 0)
        #expect(r.isError == false)
        #expect(r.timedOut == false)
        #expect(r.unresponsive == false)
    }

    @Test func nonZeroExitIsError() async {
        let r = await runner.run(
            executable: "/bin/sh", arguments: ["-c", "exit 3"],
            workingDir: nil, timeout: 10)
        #expect(r.exitCode == 3)
        #expect(r.isError)
    }

    @Test(.timeLimit(.minutes(1)))
    func timeoutTerminatesLongRun() async {
        let r = await runner.run(
            executable: "/bin/sh", arguments: ["-c", "sleep 30"],
            workingDir: nil, timeout: 1)
        #expect(r.timedOut)
        #expect(r.isError)
    }

    @Test func honorsWorkingDir() async {
        let r = await runner.run(
            executable: "/bin/sh", arguments: ["-c", "pwd"],
            workingDir: "/tmp", timeout: 10)
        #expect(r.output.contains("/tmp"))
    }

    @Test func outputOverCapIsTruncated() async {
        var smallCapRunner = SandboxProcessRunner()
        smallCapRunner.maxOutputBytes = 16
        // Produce well over 16 bytes of output.
        let r = await smallCapRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "printf '0123456789abcdefghijklmnopqrstuvwxyz'"],
            workingDir: nil, timeout: 10)
        #expect(r.output.contains("[earlier output truncated]"))
    }

    /// Invariant check for the EOF gate: a fast-exiting process must not lose
    /// output.
    ///
    /// **This is NOT a proven regression guard.** `outputOverCapIsTruncated`
    /// failed once in a full 1800-test run and passed on re-run; the suspected
    /// cause is `terminationHandler` resuming on exit while `readabilityHandler`
    /// (a different queue) had not yet fired, leaving the accumulator empty.
    /// That is consistent with the evidence and with the code shape, but it was
    /// NOT reproducible in isolation — this test passes against the pre-fix code
    /// too, at 200 iterations, with tiny and with 400 KB payloads. It appears to
    /// need full-suite CPU contention to starve the readability queue.
    /// Treat a failure here as a real signal; treat a pass as weak evidence.
    @Test func fastExitingProcessLosesNoOutput() async {
        for _ in 0..<50 {
            let r = await runner.run(
                executable: "/bin/sh",
                arguments: ["-c", "printf 'abc'"],
                workingDir: nil, timeout: 10)
            #expect(r.output == "abc")
        }
    }

    /// Guards the safety valve the EOF gate depends on: a grandchild inheriting
    /// the pipe keeps the write end open, so EOF never arrives. Waiting on EOF
    /// alone would hang here until the full timeout — this pins the post-exit
    /// grace timer that prevents that.
    @Test func grandchildHoldingPipeDoesNotStallTheCall() async {
        let started = Date()
        let r = await runner.run(
            executable: "/bin/sh",
            arguments: ["-c", "echo done; sleep 30 &"],
            workingDir: nil, timeout: 30)
        #expect(r.output.contains("done"))
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test func spawnFailureReturnsFailedResultNotCrash() async {
        let r = await runner.run(
            executable: "/nonexistent/binary/does-not-exist",
            arguments: [], workingDir: nil, timeout: 10)
        #expect(r.exitCode == -1)
        #expect(r.isError)
    }
}
