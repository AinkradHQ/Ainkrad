// Sources/Ainkrad/Core/AgentKit/Sandbox/SandboxProcessRunner.swift
import Foundation

/// The shared Process capture engine: launches `executable arguments` in
/// `workingDir`, drains combined stdout+stderr with an output cap, and enforces
/// a wall-clock timeout with SIGTERM→SIGINT escalation. Lifted verbatim from
/// RunTerminalTool so main-session behavior is byte-identical. Every local
/// backend (host/seatbelt/docker/ssh) builds argv and delegates here.
struct SandboxProcessRunner: Sendable {
    var maxOutputBytes: Int = 16 * 1024

    // Read concurrently with the process running (never after
    // waitUntilExit) so a large or endless output can't deadlock the
    // pipe. A readability handler drains the pipe as data arrives and
    // stops accumulating (terminating the process) once `maxOutputBytes`
    // is exceeded, so a flood can't grow memory unbounded. A parallel
    // wall-clock timer force-terminates a process that never produces
    // EOF (`tail -f`, `yes`, a dev server, an interactive REPL).
    func run(
        executable: String, arguments: [String],
        workingDir: String?, timeout: TimeInterval,
        onOutput: (@Sendable (String) -> Void)? = nil,
        controller: TerminalProcessController? = nil
    ) async -> ExecutionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: workingDir ?? NSHomeDirectory())
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            controller?.setActive(process)
        } catch {
            return ExecutionResult(
                output: "Could not launch: \(error.localizedDescription)",
                exitCode: -1, timedOut: false, unresponsive: false)
        }

        let handle = pipe.fileHandleForReading
        let accumulator = OutputAccumulator(cap: maxOutputBytes)

        let (timedOut, unresponsive, exitStatus): (Bool, Bool, Int32) = await withCheckedContinuation { continuation in
            let gate = ContinuationGate(continuation: continuation)

            handle.readabilityHandler = { fh in
                let chunk = fh.availableData
                guard !chunk.isEmpty else {
                    // EOF: the write end is fully closed, so everything the
                    // process ever wrote has now been accumulated. This is the
                    // only point at which the output is known to be complete.
                    gate.noteEOF()
                    return
                }
                if !accumulator.append(chunk) {
                    process.terminate()
                }
                if let onOutput {
                    onOutput(String(decoding: accumulator.snapshot(), as: UTF8.self))
                }
            }

            process.terminationHandler = { proc in
                controller?.setActive(nil)
                // Do NOT resume here on exit alone. `readabilityHandler` runs on
                // a different queue, so a process that writes and exits
                // immediately can trip `terminationHandler` while bytes are
                // still buffered — snapshotting now loses that tail. Record the
                // status and let EOF release the continuation.
                gate.noteExit(exitStatus: proc.terminationStatus)
                // Safety valve: EOF needs *every* copy of the write end closed,
                // and a spawned grandchild (`sh -c 'sleep 100 &'`) inherits one.
                // Never block the tool call on that — resume shortly after exit
                // with whatever was captured. No blocking read is used anywhere
                // here, so the pipe cannot deadlock the caller.
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                    gate.resume(exitStatus: proc.terminationStatus)
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning else { return }
                // Mark timed-out *before* signaling, so there's no race with
                // `terminationHandler` firing and reading a stale flag.
                gate.markTimedOut()
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                    guard process.isRunning else { return }
                    process.interrupt()
                    // Last-resort fallback: if the process ignores both
                    // signals, don't hang the tool call forever — resume with
                    // whatever output was captured. (`terminationHandler`
                    // firing later, if it ever does, is a no-op via the gate.)
                    // IMPORTANT: `Process.terminationStatus` traps with
                    // NSInvalidArgumentException if read while the process is
                    // still running. A command that traps both SIGTERM and
                    // SIGINT is still `isRunning` here, so it must NOT be
                    // read — resume as unresponsive instead.
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                        handle.readabilityHandler = nil
                        if process.isRunning {
                            gate.resumeUnresponsive()
                        } else {
                            gate.resume(exitStatus: process.terminationStatus)
                        }
                    }
                }
            }
        }

        // The continuation is released; nothing more should accumulate. Cleared
        // here rather than in `terminationHandler`, which must stay armed until
        // EOF so the tail of a fast-exiting process is not dropped.
        handle.readabilityHandler = nil

        let full = String(decoding: accumulator.snapshot(), as: UTF8.self)
        let output = boundedTail(full)
        return ExecutionResult(
            output: output, exitCode: exitStatus,
            timedOut: timedOut, unresponsive: unresponsive)
    }

    private func boundedTail(_ raw: String) -> String {
        let bytes = raw.utf8
        guard bytes.count > maxOutputBytes else { return raw }
        let tail = String(decoding: Array(bytes.suffix(maxOutputBytes)), as: UTF8.self)
        return "…[earlier output truncated]\n" + tail
    }
}

/// Tracks the currently-running child `Process` so `AgentSession.interrupt()` can
/// force-kill it (fixing the "task cancel doesn't kill the child" limitation
/// noted in `AgentSession.interrupt`). Lock-guarded and `@unchecked Sendable`,
/// consistent with `ContinuationGate`/`OutputAccumulator` in this file.
final class TerminalProcessController: @unchecked Sendable {
    private let lock = NSLock()
    private var active: Process?

    func setActive(_ process: Process?) {
        lock.lock()
        active = process
        lock.unlock()
    }

    /// SIGTERM the live child, then SIGINT shortly after if it's still running —
    /// the same escalation the timeout path uses. No-op when nothing is running.
    func killActive() {
        lock.lock()
        let process = active
        lock.unlock()
        guard let process, process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            if process.isRunning { process.interrupt() }
        }
    }
}

// ── moved verbatim from RunTerminalTool.swift (see Task 11 which deletes the originals) ──

/// Resumes a `CheckedContinuation` exactly once, even though the termination
/// handler and the timeout timer race each other from independent background
/// queues. Wrapping the resume-once state in a class (rather than a captured
/// local `var`) keeps every closure that touches it a plain capture of a
/// `Sendable` reference, satisfying Swift 6 strict concurrency at the
/// `@Sendable` closure boundaries `DispatchQueue`/`Process` require.
/// `@unchecked Sendable`: every mutable property is read and written under `lock`.
private final class ContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private var timedOut = false
    private var sawEOF = false
    private var pendingExit: Int32?
    private let continuation: CheckedContinuation<(Bool, Bool, Int32), Never>

    init(continuation: CheckedContinuation<(Bool, Bool, Int32), Never>) {
        self.continuation = continuation
    }

    /// Marks the run as timed-out. Must be called (and observed to complete)
    /// *before* the caller signals the process, so `resume` — however it's
    /// triggered afterwards — always reads the up-to-date flag rather than
    /// racing a `terminationHandler` callback fired by that same signal.
    func markTimedOut() {
        lock.lock()
        timedOut = true
        lock.unlock()
    }

    /// Records that the pipe hit EOF — all output is captured. Releases the
    /// continuation if the process has already exited.
    func noteEOF() {
        lock.lock()
        sawEOF = true
        let status = pendingExit
        lock.unlock()
        if let status { resume(exitStatus: status) }
    }

    /// Records the exit status without resuming. The continuation is released
    /// by whichever comes first: `noteEOF` (clean, output complete) or the
    /// caller's post-exit grace timer (a grandchild is holding the pipe open).
    func noteExit(exitStatus: Int32) {
        lock.lock()
        pendingExit = exitStatus
        let complete = sawEOF
        lock.unlock()
        if complete { resume(exitStatus: exitStatus) }
    }

    func resume(exitStatus: Int32) {
        lock.lock()
        let already = didResume
        didResume = true
        let out = timedOut
        lock.unlock()
        guard !already else { return }
        continuation.resume(returning: (out, false, exitStatus))
    }

    /// Resumes for the case where the process is still `isRunning` and
    /// could not be killed — never read `terminationStatus` here, it traps
    /// on a live `Process`. The exit status is meaningless in this case, so
    /// a sentinel value is passed through unread by the caller.
    func resumeUnresponsive() {
        lock.lock()
        let already = didResume
        didResume = true
        lock.unlock()
        guard !already else { return }
        continuation.resume(returning: (true, true, -1))
    }
}

/// Thread-safe byte accumulator for draining a process's output pipe from a
/// `FileHandle.readabilityHandler` (which fires on an arbitrary background
/// queue, outside of Swift concurrency). Stops growing once `cap` is reached
/// so a flooding command can't grow memory unbounded; `append` reports back
/// whether the caller should keep reading.
private final class OutputAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let cap: Int

    init(cap: Int) { self.cap = cap }

    /// Appends `chunk` unless the cap has already been hit. Returns `false`
    /// once the cap is reached (including on the call that crosses it), so
    /// the caller can terminate the process and stop reading.
    @discardableResult
    func append(_ chunk: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard data.count < cap else { return false }
        data.append(chunk)
        return data.count < cap
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
