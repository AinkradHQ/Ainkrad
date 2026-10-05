import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/LSP/LSPStdioTransport.swift
import Foundation

/// Spawns a local language-server subprocess and speaks Content-Length-framed
/// JSON-RPC over its stdio. Structurally a copy of MCP's `StdioTransport` —
/// same `Process`+`Pipe` spawn, same readability-handler read loop, same
/// controlled env, same `F_SETNOSIGPIPE` + throwing-write dead-process safety
/// — with the only delta being framing: Content-Length (`LSPFraming`/
/// `LSPFrameParser`) instead of MCP's newline-delimited JSON. Process
/// sandboxing is Slice 6 — the env is controlled but the process is not jailed.
actor LSPStdioTransport: MCPTransport {
    private let command: String
    private let args: [String]
    private let env: [String: String]
    private var process: Process?
    // `nonisolated(unsafe)`: `Pipe`/`FileHandle` are kernel-backed and safe to
    // touch off-actor. `send()` (actor-isolated) writes to `stdin` and the
    // `nonisolated incoming()` reads `stdout` from a `readabilityHandler`
    // callback that never runs on the actor's executor — both are required
    // to satisfy the protocol's non-actor-isolated `incoming()` requirement.
    private nonisolated(unsafe) let stdin = Pipe()
    private nonisolated(unsafe) let stdout = Pipe()

    init(command: String, args: [String], env: [String: String]) {
        self.command = command
        self.args = args
        self.env = env
    }

    func start() async throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: command)
        p.arguments = args
        // Start from the current environment (so PATH resolves node/npx/python)
        // then overlay the configured, secret-injected values.
        var merged = ProcessInfo.processInfo.environment
        for (k, v) in env { merged[k] = v }
        p.environment = merged
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = Pipe()  // drained to /dev/null implicitly (never read)
        do {
            try p.run()
        } catch {
            throw MCPError.transport("could not launch \(command): \(error.localizedDescription)")
        }
        // A dead/half-dead language server (peer closed its read end of
        // stdin) means writing to `stdin.fileHandleForWriting` hits EPIPE. By
        // default the kernel also raises SIGPIPE on the writing thread, and
        // SIGPIPE's default disposition is process termination — this fires
        // *before* `write()` even returns, so it kills the host regardless of
        // whether the write call is the throwing or non-throwing Foundation
        // API. `F_SETNOSIGPIPE` disables that signal for this specific
        // descriptor, downgrading the failure to a plain EPIPE return value,
        // which `write(contentsOf:)` in `send()` then surfaces as a catchable
        // Swift error routed into `MCPError`. Mirrors `StdioTransport`
        // (verified there empirically: without this, a write after the peer
        // closes stdin kills the process with SIGPIPE (exit 141) even through
        // `write(contentsOf:) throws`).
        var noSigPipe: Int32 = 1
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, &noSigPipe)
        process = p
    }

    func send(_ message: JSONValue) async throws {
        guard process?.isRunning == true else { throw MCPError.notConnected }
        let framed = LSPFraming.encode(message)
        // A dead/half-dead language server (peer closed its stdin read end,
        // or the process exited between the `isRunning` check above and this
        // write) is a ROUTINE failure mode, not exceptional. The older
        // non-throwing `FileHandle.write(_:)` raises an uncaught ObjC
        // exception on EPIPE, which would crash the whole host — so we use
        // the throwing `write(contentsOf:)` (macOS 10.15.4+, well under this
        // target's 14.0) which surfaces the same EPIPE as a catchable Swift
        // `Error` instead, and fold it into the same typed `MCPError` path
        // used elsewhere in `send()`/`start()`.
        do {
            try stdin.fileHandleForWriting.write(contentsOf: framed)
        } catch {
            throw MCPError.transport("write to \(command) failed: \(error.localizedDescription)")
        }
    }

    nonisolated func incoming() -> AsyncThrowingStream<JSONValue, Error> {
        let handle = stdout.fileHandleForReading
        return AsyncThrowingStream { continuation in
            let parser = LSPFrameParser()  // buffers partial frames across chunks
            handle.readabilityHandler = { fh in
                let chunk = fh.availableData
                guard !chunk.isEmpty else {
                    continuation.finish()
                    return
                }  // EOF
                for value in parser.push(chunk) { continuation.yield(value) }
            }
            continuation.onTermination = { _ in handle.readabilityHandler = nil }
        }
    }

    func stop() async {
        stdout.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
    }
}
