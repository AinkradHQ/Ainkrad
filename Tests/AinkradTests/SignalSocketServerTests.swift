import Testing
import Foundation
import AinkradSignal
@testable import Ainkrad

@MainActor
@Suite("SignalSocketServer")
final class SignalSocketServerTests {
    /// Collects payloads across the actor hop. A plain `var` captured by the
    /// server's handler would be a data race under Swift 6 — the handler is
    /// called from the accept loop's hop, not from the test's frame.
    @MainActor
    private final class Recorder {
        var payloads: [Data] = []
    }

    private func socketURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sig-\(UUID().uuidString.prefix(8)).sock")
    }

    @Test("start creates the socket file with owner-only permissions")
    func createsSocketWithMode0600() throws {
        let url = socketURL()
        let server = SignalSocketServer(url: url) { _ in .accepted }
        try server.start()
        defer { server.stop() }
        #expect(FileManager.default.fileExists(atPath: url.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let mode = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        #expect(mode == 0o600, "a world-writable socket lets any local process post as any source")
    }

    @Test("stop unlinks the socket so a relaunch can bind")
    func stopUnlinks() throws {
        let url = socketURL()
        let server = SignalSocketServer(url: url) { _ in .accepted }
        try server.start()
        server.stop()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("a stale socket file from a crash does not prevent binding")
    func rebindsOverStaleSocket() throws {
        let url = socketURL()
        FileManager.default.createFile(atPath: url.path, contents: Data())
        let server = SignalSocketServer(url: url) { _ in .accepted }
        #expect(throws: Never.self) { try server.start() }
        server.stop()
    }

    @Test("a payload written to the socket reaches the handler")
    func deliversToHandler() async throws {
        let url = socketURL()
        let recorder = Recorder()
        let server = SignalSocketServer(url: url) { data in
            recorder.payloads.append(data)
            return .accepted
        }
        try server.start()
        defer { server.stop() }

        try SignalSocketClient.send(Data("{\"token\":\"t\"}\n".utf8), to: url)
        try await Task.sleep(for: .milliseconds(300))
        #expect(recorder.payloads.count == 1)
        #expect(String(decoding: recorder.payloads[0], as: UTF8.self) == "{\"token\":\"t\"}")
    }

    @Test("a payload past the cap is refused without being buffered whole")
    func refusesOversizedWithoutBuffering() async throws {
        // The point is that the server stops reading once it knows the payload
        // is too large, rather than allocating whatever a peer chooses to send.
        let url = socketURL()
        let recorder = Recorder()
        let server = SignalSocketServer(url: url) { data in
            recorder.payloads.append(data)
            return .accepted
        }
        try server.start()
        defer { server.stop() }

        let oversized = Data(String(repeating: "x", count: 32 * 1024).utf8) + Data("\n".utf8)
        try? SignalSocketClient.send(oversized, to: url)
        try await Task.sleep(for: .milliseconds(300))
        #expect(recorder.payloads.isEmpty, "an oversized payload never reaches policy")
    }

    @Test("the server survives a peer that connects and disconnects saying nothing")
    func survivesSilentPeer() async throws {
        // A health check, a port scanner, or a CLI killed mid-write. If this
        // wedges the accept loop, external ingress dies silently for the rest
        // of the session.
        let url = socketURL()
        let recorder = Recorder()
        let server = SignalSocketServer(url: url) { data in
            recorder.payloads.append(data)
            return .accepted
        }
        try server.start()
        defer { server.stop() }

        try SignalSocketClient.send(Data(), to: url)
        try await Task.sleep(for: .milliseconds(150))
        try SignalSocketClient.send(Data("{\"token\":\"t\"}\n".utf8), to: url)
        try await Task.sleep(for: .milliseconds(300))
        #expect(recorder.payloads.count == 1, "the loop still accepts after an empty connection")
    }
    @Test("a path too long for sockaddr_un is refused, not silently truncated")
    func refusesOverlongPath() {
        // sun_path is a fixed ~104-byte C array. strncpy would happily
        // truncate, and the server would then bind a path the CLI never looks
        // at — external ingress silently dead with a socket file sitting right
        // there. Checked rather than truncated.
        let long = FileManager.default.temporaryDirectory
            .appendingPathComponent(String(repeating: "d", count: 120))
            .appendingPathComponent("signal.sock")
        let server = SignalSocketServer(url: long) { _ in .accepted }
        #expect(throws: SignalSocketServer.StartFailure.pathTooLong(length: long.path.utf8.count)) {
            try server.start()
        }
    }

    @Test("sending to a socket nobody is listening on fails as notListening")
    func sendWithNoListener() {
        // This is the ORDINARY case for `ainkrad notify`: the host is not
        // running. It must be a clean, identifiable error the CLI can turn
        // into exit 0 with a warning, not a crash and not a hang.
        let url = socketURL()
        #expect(throws: SignalSocketClient.SendFailure.self) {
            try SignalSocketClient.send(Data("{}\n".utf8), to: url)
        }
    }
}
