import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/MCP/HTTPSSETransport.swift
import Foundation

/// Streamable-HTTP/SSE MCP transport for remote servers. HTTPS is enforced at
/// `start()`. Auth header *values* come from config/SecretStore and are only
/// ever attached to the outbound `URLRequest` — never logged or included in
/// any thrown error text.
///
/// Reuses the provider stack's `StreamingHTTPClient` + `SSEParser` — no new
/// HTTP or SSE machinery lives in this file. The streamable-HTTP MCP shape
/// implemented here is per-request POST-then-stream inside `send`: a
/// long-lived GET SSE channel with reconnect/backoff is a fast-follow, not in
/// scope for this slice.
actor HTTPSSETransport: MCPTransport {
    private let endpoint: URL
    private let authHeaders: [String: String]
    private let http: any StreamingHTTPClient
    // `incoming()` is a synchronous, non-async protocol requirement, so Swift 6
    // rejects an actor-isolated conformance for it (see the same note on
    // `StubMCPTransport`/`StdioTransport`). The continuation is therefore
    // stored outside actor isolation in a lock-protected box.
    private let box = MCPSharedContinuationBox()

    init(
        endpoint: URL, authHeaders: [String: String],
        http: any StreamingHTTPClient = URLSessionStreamingHTTPClient()
    ) {
        self.endpoint = endpoint
        self.authHeaders = authHeaders
        self.http = http
    }

    func start() async throws {
        guard endpoint.scheme?.lowercased() == "https" else {
            throw MCPError.transport("MCP HTTP endpoints must be HTTPS: \(endpoint.absoluteString)")
        }
    }

    func send(_ message: JSONValue) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        for (key, value) in authHeaders { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = try? JSONSerialization.data(withJSONObject: message.toFoundationObject())

        let bytes: AsyncThrowingStream<Data, Error>
        do {
            bytes = try await http.post(request)
        } catch let StreamingHTTPError.status(code, body) {
            throw MCPError.transport("HTTP \(code): \(body)")
        } catch {
            throw MCPError.transport(String(describing: error))
        }

        // Tee the raw bytes: feed `SSEParser`, but also accumulate the whole
        // body so a plain-JSON (non-SSE) response can still be parsed once if
        // no `data:` events were ever seen.
        let accumulator = RawBodyAccumulator()
        var sawEvent = false
        do {
            for try await payload in SSEParser.events(from: tee(bytes, into: accumulator)) {
                sawEvent = true
                // Malformed/partial SSE payload: skip it, never crash.
                if let value = JSONValue.parse(payload) { box.yield(value) }
            }
        } catch let StreamingHTTPError.status(code, body) {
            throw MCPError.transport("HTTP \(code): \(body)")
        } catch {
            throw MCPError.transport(String(describing: error))
        }

        if !sawEvent {
            let raw = accumulator.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty, let value = JSONValue.parse(raw) {
                box.yield(value)
            }
        }
    }

    nonisolated func incoming() -> AsyncThrowingStream<JSONValue, Error> {
        AsyncThrowingStream { continuation in box.set(continuation) }
    }

    func stop() async { box.finish() }

    /// Forwards each chunk downstream to `SSEParser` while also appending it
    /// to `accumulator`, so the raw body survives even though `SSEParser`
    /// consumes the stream.
    private nonisolated func tee(
        _ upstream: AsyncThrowingStream<Data, Error>, into accumulator: RawBodyAccumulator
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { cont in
            let task = Task {
                do {
                    for try await chunk in upstream {
                        accumulator.append(chunk)
                        cont.yield(chunk)
                    }
                    cont.finish()
                } catch {
                    cont.finish(throwing: error)
                }
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }
}

/// Thread-safe accumulator for the raw response body, so it can be inspected
/// after `SSEParser` has consumed the teed stream. Only ever touched from the
/// single `tee` producer task and read back from `send()` after that task's
/// stream has finished, but kept lock-protected for safety since both sides
/// are `Sendable` closures.
private final class RawBodyAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    var body: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}
