import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/LSP/LSPClient.swift
import Foundation

/// One JSON-RPC client per running language server. Owns the transport,
/// performs the LSP `initialize`/`initialized` handshake, tracks document
/// sync versions, caches pushed `textDocument/publishDiagnostics`
/// notifications by URI, and issues bounded formatting requests.
///
/// This is a near-verbatim port of `MCPClient`'s request/response
/// correlation and continuation-leak safety (see that file's header comment)
/// with one structural addition: LSP diagnostics arrive as server-initiated
/// **notifications**, not responses to a request. `MCPClient` simply ignores
/// notifications; `LSPClient`'s read loop instead routes
/// `textDocument/publishDiagnostics` into a `[uri: [LSPDiagnostic]]` cache
/// before falling through to the same response-correlation path MCP uses.
/// Continuation-leak safety: every `withCheckedContinuation` created in
/// `request(method:params:)` is registered in `pending` BEFORE the outbound
/// send happens, and there are exactly three ways it can be resumed —
/// (1) a matching response arrives (`resolve`), (2) the send itself throws
/// (`resolve` called inline), or (3) a timeout task fires, or (4)
/// `initialize` failure / `shutdown()` calls `failAllPending`. There is no
/// path that drops a continuation without resuming it, so a caller can never
/// hang forever.
actor LSPClient {
    private let transport: any MCPTransport
    private var readLoop: Task<Void, Never>?
    private var nextID = 0
    private var pending: [String: CheckedContinuation<Result<JSONValue, MCPError>, Never>] = [:]
    private var timeouts: [String: Task<Void, Never>] = [:]
    private var diagnosticsByURI: [String: [LSPDiagnostic]] = [:]
    private var documentVersions: [String: Int] = [:]
    private(set) var serverCapabilities: JSONValue = .object([:])
    private(set) var isInitialized = false
    private let requestTimeoutNanos: UInt64

    /// - Parameter requestTimeout: hard ceiling (seconds) on any single
    ///   request/response round-trip, including the `initialize` handshake and
    ///   `textDocument/formatting`. A language server that never answers
    ///   (hung process, half-open pipe) fails the awaiting call with a typed
    ///   `.transport` error instead of blocking the caller forever.
    init(transport: any MCPTransport, requestTimeout: TimeInterval = 30) {
        self.transport = transport
        self.requestTimeoutNanos = UInt64(max(0.1, requestTimeout) * 1_000_000_000)
    }

    /// Performs the LSP handshake: `initialize` (with minimal client
    /// capabilities and the given `rootUri`) → server capabilities →
    /// `initialized` notification.
    func initialize(rootURI: String) async throws {
        try await transport.start()
        startReadLoop()
        let processId = Int(ProcessInfo.processInfo.processIdentifier)
        let params = LSPRPC.initializeParams(processId: processId, rootUri: rootURI)
        do {
            let result = try await request(method: "initialize", params: params)
            serverCapabilities = result["capabilities"] ?? .object([:])
            try await transport.send(LSPRPC.initializedNotification())
            isInitialized = true
        } catch {
            // Handshake failed — fully tear down instead of leaving a
            // half-open session: cancel the read loop, STOP the transport
            // (the only path that terminates a spawned server process), fail
            // any pending waiters, surface a typed error.
            readLoop?.cancel()
            readLoop = nil
            await transport.stop()
            failAllPending(.notConnected)
            throw error
        }
    }

    /// `textDocument/didOpen` — a notification (no response). Seeds the
    /// document's sync version at 1.
    func didOpen(uri: String, languageId: String, text: String) async throws {
        documentVersions[uri] = 1
        try await transport.send(
            LSPRPC.didOpenNotification(
                uri: uri, languageId: languageId, version: 1, text: text))
    }

    /// `textDocument/didChange` — a notification (no response), full-document
    /// sync. Bumps the tracked version for `uri`.
    func didChange(uri: String, text: String) async throws {
        let version = (documentVersions[uri] ?? 0) + 1
        documentVersions[uri] = version
        try await transport.send(LSPRPC.didChangeNotification(uri: uri, version: version, text: text))
    }

    /// Cached diagnostics for `uri`, most recently pushed by the server via
    /// `textDocument/publishDiagnostics`. Empty if none have arrived yet.
    func diagnostics(for uri: String) -> [LSPDiagnostic] {
        diagnosticsByURI[uri] ?? []
    }

    /// `textDocument/formatting` — a bounded request returning `[TextEdit]`
    /// (empty when the server reports no edits needed).
    func formatting(uri: String) async throws -> [LSPTextEdit] {
        let params = JSONValue.object([
            "textDocument": .object(["uri": .string(uri)]),
            "options": .object(["tabSize": .number(4), "insertSpaces": .bool(true)]),
        ])
        let result = try await request(method: "textDocument/formatting", params: params)
        return LSPRPC.decodeFormattingResult(result)
    }

    /// Best-effort `shutdown` request followed by the `exit` notification,
    /// then tears down the transport unconditionally — mirrors the spec's
    /// shutdown sequence without letting a non-responsive server block
    /// process teardown.
    func shutdown() async {
        _ = try? await request(method: "shutdown", params: .object([:]))
        try? await transport.send(LSPRPC.notification(method: "exit", params: .object([:])))
        readLoop?.cancel()
        readLoop = nil
        await transport.stop()
        failAllPending(.notConnected)
        isInitialized = false
    }

    // MARK: - internals

    private func request(method: String, params: JSONValue) async throws -> JSONValue {
        nextID += 1
        let id = String(nextID)
        let message = LSPRPC.request(id: id, method: method, params: params)
        let timeoutNanos = requestTimeoutNanos
        let outcome = await withCheckedContinuation { (cont: CheckedContinuation<Result<JSONValue, MCPError>, Never>) in
            pending[id] = cont
            Task {
                do { try await transport.send(message) } catch {
                    await self.resolve(id: id, .failure(.transport(String(describing: error))))
                }
            }
            // Bounded round-trip: if no response is correlated within the
            // ceiling, resolve the waiter with a typed error. `resolve`
            // no-ops if a real response already arrived, so this never
            // double-resumes; and `resolve` cancels this task when a real
            // response wins, so a prompt reply leaves no lingering sleep.
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
        guard !MCPRPC.isNotification(message) else {
            // Server-initiated notifications are routed by method, never
            // resolved against `pending` — there is no request waiting on
            // them. `publishDiagnostics` is the one this slice acts on;
            // anything else is dropped (mirrors MCPClient's v1 behavior).
            if message["method"]?.stringValue == "textDocument/publishDiagnostics",
                let uri = message["params"]?["uri"]?.stringValue
            {
                diagnosticsByURI[uri] = LSPRPC.decodeDiagnostics(message["params"] ?? .object([:]))
            }
            return
        }
        switch MCPRPC.decodeResponse(message) {
        case .success(let (id, result)): resolve(id: id, .success(result))
        case .failure(let error):
            if let id = message["id"]?.stringValue {
                resolve(id: id, .failure(error))
            } else {
                Log.lsp.error("dropped malformed LSP message (no id, not a notification)")
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
}
