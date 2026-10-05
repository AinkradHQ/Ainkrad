import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/MCP/MCPTransport.swift
import Foundation

/// A bidirectional JSON-RPC message pipe to one MCP server. Framing is the
/// transport's concern; `MCPClient` only sees decoded `JSONValue` messages.
protocol MCPTransport: Sendable {
    func start() async throws
    func send(_ message: JSONValue) async throws
    /// One long-lived stream of inbound messages, established at `start()`.
    func incoming() -> AsyncThrowingStream<JSONValue, Error>
    func stop() async
}

/// In-memory transport for `MCPClient` tests: capture outbound, inject inbound.
actor StubMCPTransport: MCPTransport {
    private(set) var sent: [JSONValue] = []
    /// Test observability: how many times `stop()` has been called.
    private(set) var stopCount = 0
    // The protocol requires `incoming()` to be callable without actor
    // isolation (Swift 6 rejects an actor-isolated conformance for a
    // synchronous, non-async requirement), so the continuation itself is
    // stored outside actor isolation in a lock-protected box rather than in
    // an actor-isolated `var` — mirrors the `@unchecked Sendable` + `NSLock`
    // pattern `RunTerminalTool`'s `OutputAccumulator` uses for the same
    // cross-isolation reason.
    private let box = MCPSharedContinuationBox()
    /// Auto-responder invoked for each sent message; return messages to inject.
    var responder: (@Sendable (JSONValue) -> [JSONValue])?

    init(responder: (@Sendable (JSONValue) -> [JSONValue])? = nil) {
        self.responder = responder
    }

    func start() async throws {}

    func send(_ message: JSONValue) async throws {
        sent.append(message)
        for reply in responder?(message) ?? [] { box.yield(reply) }
    }

    nonisolated func incoming() -> AsyncThrowingStream<JSONValue, Error> {
        AsyncThrowingStream { continuation in box.set(continuation) }
    }

    /// Test hook: push an unsolicited inbound message.
    func inject(_ message: JSONValue) { box.yield(message) }

    func stop() async {
        stopCount += 1
        box.finish()
    }
}

/// Thread-safe holder for an `AsyncThrowingStream` continuation, so a
/// `nonisolated` protocol requirement (`incoming()`) can hand the
/// continuation to a `send`/`inject` call made from the actor without
/// crossing actor isolation for the reference itself. `Continuation.yield`
/// and `.finish()` are safe to call concurrently by design.
/// Shared by `StubMCPTransport` and `InProcessTransport` — both need to hand a
/// continuation from a `nonisolated incoming()` to an isolated `send`. Not
/// `private`: internal so `InProcessTransport` (a different file) can use it.
/// Named `MCPSharedContinuationBox` (not the bare `ContinuationBox` name) so
/// the "Shared" distinguishes it from two unrelated, file-private boxes that
/// happen to sit in the same module: the `private final class
/// MCPContinuationBox` in `HTTPSSETransport.swift`, and the `private final
/// class ContinuationBox` in `Voice/OnDeviceTranscriptionBackend.swift`. Both
/// stay file-private and untouched — those are distinct types, not this one.
final class MCPSharedContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<JSONValue, Error>.Continuation?
    // Values/finish that arrive BEFORE a consumer attaches are buffered and
    // flushed on `set()`, so a reply yielded before the read loop starts
    // consuming `incoming()` is never dropped. Without this, MCPClient.connect()
    // could send `initialize` and have the reply yielded before its read-loop
    // Task attached — the reply vanished and the request stalled to its timeout.
    // (Real Stdio/HTTP transports are shielded by pipe/socket buffering; this
    // makes the in-memory stub behave the same way.)
    private var buffered: [JSONValue] = []
    private var finished = false

    func set(_ continuation: AsyncThrowingStream<JSONValue, Error>.Continuation) {
        lock.lock()
        self.continuation = continuation
        let pending = buffered
        buffered.removeAll()
        let didFinish = finished
        lock.unlock()
        for value in pending { continuation.yield(value) }
        if didFinish { continuation.finish() }
    }

    func yield(_ value: JSONValue) {
        lock.lock()
        if let c = continuation {
            lock.unlock()
            c.yield(value)
        } else {
            buffered.append(value)
            lock.unlock()
        }
    }

    func finish() {
        lock.lock()
        if let c = continuation {
            lock.unlock()
            c.finish()
        } else {
            finished = true
            lock.unlock()
        }
    }
}
