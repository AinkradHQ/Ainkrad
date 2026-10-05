import Foundation
import Network

struct CallbackResult: Equatable {
    let code: String
    let state: String
}
enum LoopbackError: Error, Equatable { case bindFailed, timedOut, malformedCallback }

/// One-shot loopback HTTP listener on 127.0.0.1:<port>. Captures the OAuth
/// redirect's `code`/`state`, serves a "you can close this tab" page, then stops.
actor LoopbackCallbackServer {
    private let port: UInt16
    private var listener: NWListener?
    private var continuation: CheckedContinuation<CallbackResult, Error>?

    init(port: UInt16 = 53692) { self.port = port }

    /// Pure parser for the callback query string.
    static func parseCallback(query: String) throws -> CallbackResult {
        var comps = URLComponents()
        comps.query = query
        let items = comps.queryItems ?? []
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw LoopbackError.malformedCallback
        }
        let state = items.first(where: { $0.name == "state" })?.value ?? ""
        return CallbackResult(code: code, state: state)
    }

    func waitForCallback(timeout: TimeInterval) async throws -> CallbackResult {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw LoopbackError.bindFailed
        }

        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: nwPort)

        let listener: NWListener
        do {
            listener = try NWListener(using: params)
        } catch { throw LoopbackError.bindFailed }
        self.listener = listener

        return try await withCheckedThrowingContinuation { cont in
            Task { await self.start(listener: listener, timeout: timeout, continuation: cont) }
        }
    }

    private func start(
        listener: NWListener,
        timeout: TimeInterval,
        continuation: CheckedContinuation<CallbackResult, Error>
    ) {
        // If a previous run left a continuation dangling, this instance is
        // one-shot per waitForCallback call, so this should never happen —
        // guard anyway rather than silently dropping a continuation.
        guard self.continuation == nil else { return }
        self.continuation = continuation

        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { await self.handle(connection: connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .failed = state {
                Task { await self.finish(.failure(LoopbackError.bindFailed)) }
            }
        }
        listener.start(queue: .global())

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(timeout, 0) * 1_000_000_000))
            await self?.finish(.failure(LoopbackError.timedOut))
        }
    }

    /// Resumes the pending continuation exactly once and tears down the
    /// listener. Every subsequent call (a second connection, the timeout
    /// firing after success, a listener failure after resume, etc.) is a
    /// safe no-op.
    private func finish(_ result: Result<CallbackResult, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        listener?.newConnectionHandler = nil
        listener?.stateUpdateHandler = nil
        listener?.cancel()
        listener = nil

        switch result {
        case .success(let value): continuation.resume(returning: value)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }

    private func handle(connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            if case .failed = state { connection.cancel() }
        }
        connection.start(queue: .global())
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self else { return }
            Task { await self.process(data: data, connection: connection) }
        }
    }

    private func process(data: Data?, connection: NWConnection) {
        guard let data, let request = String(data: data, encoding: .utf8),
            let firstLine = request.split(separator: "\r\n").first,
            let rawPath = firstLine.split(separator: " ").dropFirst().first
        else {
            respond(on: connection, status: "400 Bad Request", body: nil)
            return
        }

        let pathString = String(rawPath)
        let path: Substring
        let query: String
        if let queryStart = pathString.firstIndex(of: "?") {
            path = pathString[pathString.startIndex..<queryStart]
            query = String(pathString[pathString.index(after: queryStart)...])
        } else {
            path = pathString[...]
            query = ""
        }

        // Ignore requests to anything but the OAuth redirect path (browser
        // favicon/prefetch requests, etc.) without touching the pending
        // continuation — only /callback can resolve or fail the wait.
        guard path == "/callback" else {
            respond(on: connection, status: "404 Not Found", body: nil)
            return
        }

        do {
            let result = try Self.parseCallback(query: query)
            respond(
                on: connection,
                status: "200 OK",
                body: "<html><body style='font-family:-apple-system'>Signed in. You can close this tab.</body></html>"
            )
            finish(.success(result))
        } catch {
            respond(on: connection, status: "400 Bad Request", body: nil)
            finish(.failure(error))
        }
    }

    private nonisolated func respond(on connection: NWConnection, status: String, body: String?) {
        let html = body ?? ""
        let response =
            "HTTP/1.1 \(status)\r\nContent-Type: text/html\r\nContent-Length: \(html.utf8.count)\r\n\r\n" + html
        connection.send(
            content: Data(response.utf8),
            completion: .contentProcessed { _ in
                connection.cancel()
            })
    }
}
