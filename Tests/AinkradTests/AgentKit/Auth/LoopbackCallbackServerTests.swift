import Testing
import Foundation
import Network
import Darwin
@testable import Ainkrad

@Suite struct LoopbackCallbackServerTests {
    @Test func parsesCodeAndStateFromQuery() throws {
        let r = try LoopbackCallbackServer.parseCallback(query: "code=ABC&state=XYZ")
        #expect(r == CallbackResult(code: "ABC", state: "XYZ"))
    }

    @Test func rejectsQueryMissingCode() {
        #expect(throws: LoopbackError.malformedCallback) {
            _ = try LoopbackCallbackServer.parseCallback(query: "state=XYZ")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsRealCallbackOverSocket() async throws {
        let testPort = Self.freeLoopbackPort()
        let server = LoopbackCallbackServer(port: testPort)

        async let waited = server.waitForCallback(timeout: 20)

        // Give the listener a moment to bind before the client connects.
        try await Task.sleep(nanoseconds: 200_000_000)
        try await sendRawHTTPRequest(
            to: testPort,
            requestLine: "GET /callback?code=ABC&state=XYZ HTTP/1.1\r\nHost: localhost\r\n\r\n"
        )

        let result = try await waited
        #expect(result == CallbackResult(code: "ABC", state: "XYZ"))
    }

    @Test(.timeLimit(.minutes(1)))
    func timesOutWithoutAConnection() async throws {
        let testPort = Self.freeLoopbackPort()
        let server = LoopbackCallbackServer(port: testPort)

        await #expect(throws: LoopbackError.timedOut) {
            _ = try await server.waitForCallback(timeout: 0.5)
        }
    }

    /// Asks the OS for a currently-free loopback port.
    ///
    /// These tests used fixed ports (58423/58424), which made
    /// `timesOutWithoutAConnection` flaky under full-suite load — and flaky in a
    /// misleading way. `LoopbackCallbackServer` sets `requiredLocalEndpoint`, so
    /// a port still held by an earlier run puts the listener in `.failed` and
    /// `waitForCallback` throws `bindFailed`; the test then fails asserting
    /// `timedOut`, which reads as a timeout bug rather than a port collision.
    ///
    /// Binding with port 0 and reading back what the kernel assigned is not
    /// race-free — the port is released before the server claims it — but it is
    /// vastly better than a constant, because nothing else in the suite or on
    /// the machine is likely to take that specific ephemeral port in the
    /// microseconds between.
    static func freeLoopbackPort() -> UInt16 {
        let handle = socket(AF_INET, SOCK_STREAM, 0)
        guard handle >= 0 else { return 58_423 }
        defer { close(handle) }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0                                  // let the kernel choose
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(handle, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return 58_423 }

        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let read = withUnsafeMutablePointer(to: &assigned) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(handle, $0, &length)
            }
        }
        guard read == 0 else { return 58_423 }
        return UInt16(bigEndian: assigned.sin_port)
    }

    /// Opens a raw TCP connection to 127.0.0.1:port and writes an HTTP
    /// request line, exercising the server's real socket path end to end.
    private func sendRawHTTPRequest(to port: UInt16, requestLine: String) async throws {
        let connection = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )

        let resumeGuard = ResumeOnceGuard()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: Data(requestLine.utf8), completion: .contentProcessed { error in
                        guard resumeGuard.claim() else { return }
                        if let error { cont.resume(throwing: error) } else { cont.resume(returning: ()) }
                    })
                case .failed(let error):
                    guard resumeGuard.claim() else { return }
                    cont.resume(throwing: error)
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
        connection.cancel()
    }
}

/// Thread-safe single-claim latch so a `CheckedContinuation` captured across
/// multiple `NWConnection` callback paths is resumed exactly once.
private final class ResumeOnceGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
