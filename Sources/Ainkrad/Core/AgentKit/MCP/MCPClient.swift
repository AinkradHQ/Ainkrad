import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/MCP/MCPClient.swift
import Foundation

/// One JSON-RPC client per configured MCP server. Owns the transport, performs
/// the MCP handshake, and correlates requests to responses by id. Malformed
/// inbound messages are logged and skipped — a bad frame never wedges a session.
///
/// Continuation-leak safety: every `withCheckedContinuation` created in
/// `request(method:params:)` is registered in `pending` BEFORE the outbound
/// send happens, and there are exactly three ways it can be resumed —
/// (1) a matching response arrives (`resolve`), (2) the send itself throws
/// (`resolve` called inline), or (3) `disconnect()`/a read-loop failure calls
/// `failAllPending`. There is no path that drops a continuation without
/// resuming it, so a caller can never hang forever.
actor MCPClient {
    private let transport: any MCPTransport
    private var readLoop: Task<Void, Never>?
    private var nextID = 0
    private var pending: [String: CheckedContinuation<Result<JSONValue, MCPError>, Never>] = [:]
    private var timeouts: [String: Task<Void, Never>] = [:]
    private(set) var serverCapabilities: JSONValue = .object([:])
    private(set) var isConnected = false
    private let requestTimeoutNanos: UInt64

    /// - Parameter requestTimeout: hard ceiling (seconds) on any single
    ///   request/response round-trip, including the `initialize` handshake. A
    ///   server that never answers (hung process, half-open socket) fails the
    ///   awaiting call with a typed `.transport` error instead of blocking the
    ///   caller — and, in tests, instead of wedging the whole suite forever.
    init(transport: any MCPTransport, requestTimeout: TimeInterval = 30) {
        self.transport = transport
        self.requestTimeoutNanos = UInt64(max(0.1, requestTimeout) * 1_000_000_000)
    }

    func connect() async throws {
        try await transport.start()
        startReadLoop()
        let params = JSONValue.object([
            "protocolVersion": .string("2024-11-05"),
            "clientInfo": .object(["name": .string("Ainkrad"), "version": .string("1.0")]),
            "capabilities": .object(["tools": .object([:])]),
        ])
        do {
            let result = try await request(method: "initialize", params: params)
            serverCapabilities = result["capabilities"] ?? .object([:])
            try await transport.send(
                MCPRPC.notification(
                    method: "notifications/initialized",
                    params: .object([:])))
            isConnected = true
        } catch {
            // Handshake failed (server error, transport drop, unexpected
            // shape) — fully tear down instead of leaving a half-open session:
            // cancel the read loop, STOP the transport (StdioTransport.stop is
            // the only path that terminates the spawned child process — skipping
            // it here leaks a live process), fail pending, surface a typed error.
            readLoop?.cancel()
            readLoop = nil
            await transport.stop()
            failAllPending(.notConnected)
            throw error
        }
    }

    func listTools() async throws -> [MCPToolDescriptor] {
        MCPRPC.decodeToolList(try await request(method: "tools/list", params: .object([:])))
    }

    func callTool(name: String, arguments: JSONValue) async throws -> String {
        let params = JSONValue.object(["name": .string(name), "arguments": arguments])
        let result = try await request(method: "tools/call", params: params)
        if case .bool(true)? = result["isError"] {
            throw MCPError.protocolError(Self.flatten(result))
        }
        return Self.flatten(result)
    }

    func listResources() async throws -> [MCPResourceDescriptor] {
        MCPRPC.decodeResourceList(try await request(method: "resources/list", params: .object([:])))
    }

    func readResource(uri: String) async throws -> String {
        let params = JSONValue.object(["uri": .string(uri)])
        let result = try await request(method: "resources/read", params: params)
        let text = MCPRPC.flattenResourceContents(result)
        // Mirrors `callTool`'s isError handling. `resources/read` has no spec'd
        // failure flag, so the SDK carries one alongside `contents` under the
        // same `ainkrad/` namespace as the requiresLiveApp annotation. Without
        // this the caller would hand "no terminal is currently open" to the
        // model as if it were the buffer.
        if case .bool(true)? = result["ainkrad/isError"] {
            throw MCPError.resourceFailure(text)
        }
        return text
    }

    func disconnect() async {
        readLoop?.cancel()
        readLoop = nil
        await transport.stop()
        failAllPending(.notConnected)
        isConnected = false
    }

    /// Reconnects with a bounded number of attempts and a capped exponential
    /// backoff between them — never an unbounded retry loop, and never a
    /// blocking sleep on the actor's executor across attempts longer than the
    /// ceiling. Throws the last observed error once attempts are exhausted.
    func reconnect(maxAttempts: Int = 3) async throws {
        precondition(maxAttempts > 0, "reconnect requires at least one attempt")
        await disconnect()
        var lastError: MCPError = .notConnected
        for attempt in 1...maxAttempts {
            do {
                try await connect()
                return
            } catch let error as MCPError {
                lastError = error
            } catch {
                lastError = .transport(String(describing: error))
            }
            if attempt < maxAttempts {
                let backoffMs = min(100 * (1 << attempt), 2_000)  // ceiling: 2s
                try? await Task.sleep(nanoseconds: UInt64(backoffMs) * 1_000_000)
            }
        }
        throw lastError
    }

    // MARK: - internals

    private func request(method: String, params: JSONValue) async throws -> JSONValue {
        nextID += 1
        let id = String(nextID)
        let message = MCPRPC.request(id: id, method: method, params: params)
        let timeoutNanos = requestTimeoutNanos
        let outcome = await withCheckedContinuation { (cont: CheckedContinuation<Result<JSONValue, MCPError>, Never>) in
            pending[id] = cont
            Task {
                do { try await transport.send(message) } catch {
                    await self.resolve(id: id, .failure(.transport(String(describing: error))))
                }
            }
            // Bounded round-trip: if no response is correlated within the
            // ceiling, resolve the waiter with a typed error. `resolve` no-ops
            // if a real response already arrived, so this never double-resumes;
            // and `resolve` cancels this task when a real response wins, so a
            // prompt reply leaves no lingering sleep.
            timeouts[id] = Task {
                try? await Task.sleep(nanoseconds: timeoutNanos)
                await self.resolve(id: id, .failure(.transport("request '\(method)' timed out")))
            }
        }
        switch outcome {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }

    private func startReadLoop() {
        readLoop = Task { [weak self] in
            guard let self else { return }
            do {
                for try await message in await self.transport.incoming() {
                    if Task.isCancelled { return }
                    await self.handle(message)
                }
            } catch {
                await self.failAllPending(.transport(String(describing: error)))
            }
        }
    }

    private func handle(_ message: JSONValue) {
        guard !MCPRPC.isNotification(message) else { return }  // ignore server notifications in v1
        switch MCPRPC.decodeResponse(message) {
        case .success(let (id, result)): resolve(id: id, .success(result))
        case .failure(let error):
            if let id = message["id"]?.stringValue {
                resolve(id: id, .failure(error))
            } else {
                Log.mcp.error("dropped malformed MCP message (no id, not a notification)")
            }
        }
    }

    /// Resolves the pending continuation for `id`, if any waiter is still
    /// registered. An id with no matching waiter (unsolicited/unknown/stale)
    /// is dropped silently — never crashes, never blocks anything, since
    /// there is nothing waiting on it.
    private func resolve(id: String, _ outcome: Result<JSONValue, MCPError>) {
        timeouts.removeValue(forKey: id)?.cancel()
        guard let cont = pending.removeValue(forKey: id) else { return }
        cont.resume(returning: outcome)
    }

    private func failAllPending(_ error: MCPError) {
        for t in timeouts.values { t.cancel() }
        timeouts.removeAll()
        for cont in pending.values { cont.resume(returning: .failure(error)) }
        pending.removeAll()
    }

    /// Flatten an MCP tool result's `content` array into plain text.
    private static func flatten(_ result: JSONValue) -> String {
        guard case .array(let items)? = result["content"] else { return "" }
        return items.compactMap { $0["text"]?.stringValue }.joined(separator: "\n")
    }
}
