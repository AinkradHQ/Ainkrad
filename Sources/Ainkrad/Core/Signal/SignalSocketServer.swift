import Foundation
import AinkradSignal

/// Plumbing only: an `AF_UNIX` listener that moves bytes to a handler and a
/// reply back. Every policy decision lives in `SignalIngressCoordinator`, so
/// there is deliberately almost nothing here to get wrong.
///
/// **A socket failure must never be a launch failure.** External ingress is
/// supplementary — in-process emission (M2) does not touch this path — so
/// `start()` reports a problem to its caller, which records one `.host`
/// warning and carries on. The app launching without external ingress is a
/// degraded feature; the app not launching is an outage.
@MainActor
final class SignalSocketServer {
    enum StartFailure: Error, Equatable {
        case socketUnavailable(errno: Int32)
        case bindFailed(errno: Int32)
        case listenFailed(errno: Int32)
        /// The path is longer than `sockaddr_un.sun_path`, which is ~104 bytes
        /// on Darwin. Checked rather than truncated: a silently shortened path
        /// binds a socket nobody can find.
        case pathTooLong(length: Int)
    }

    private let url: URL
    private let handler: @MainActor (Data) -> SignalIngressResult
    private var listeningFD: Int32?
    private var acceptSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.ainkrad.signal.socket")

    init(url: URL, handler: @escaping @MainActor (Data) -> SignalIngressResult) {
        self.url = url
        self.handler = handler
    }

    func start() throws {
        let path = url.path
        // `sun_path` is a fixed-size C array. Anything longer cannot be
        // represented, and truncation would bind a different path than the CLI
        // will look for.
        let capacity = MemoryLayout.size(ofValue: sockaddr_un().sun_path)
        guard path.utf8.count < capacity else {
            throw StartFailure.pathTooLong(length: path.utf8.count)
        }

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        // Unlink whatever is there first. After a crash the previous socket
        // file survives, and `bind` on an existing path fails with EADDRINUSE
        // — which would mean one hard shutdown permanently disables external
        // ingress until somebody deletes a file by hand.
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw StartFailure.socketUnavailable(errno: errno) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &address.sun_path) { destination in
            path.withCString { source in
                strncpy(UnsafeMutableRawPointer(destination).assumingMemoryBound(to: CChar.self),
                        source, capacity - 1)
            }
        }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
        }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw StartFailure.bindFailed(errno: code)
        }

        // Immediately after bind, before anyone can connect. The process umask
        // decides the mode `bind` creates, so without this a socket can land
        // group- or world-writable — and on this socket, write access IS the
        // ability to post as any source whose token you can guess. Narrowing it
        // is not defence in depth, it is the door.
        chmod(path, 0o600)

        guard listen(fd, 16) == 0 else {
            let code = errno
            close(fd)
            unlink(path)
            throw StartFailure.listenFailed(errno: code)
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        let handler = self.handler

        // Both handlers are declared `@Sendable` EXPLICITLY, and that is not
        // decoration. `start()` is `@MainActor`, so a bare closure written
        // here inherits main-actor isolation — and libdispatch then runs it on
        // its own queue, where Swift's isolation assertion trips and traps the
        // process (`dispatch_assert_queue_fail` via
        // `swift_task_checkIsolated`). A `@Sendable` closure is nonisolated,
        // which is what a dispatch handler must be.
        //
        // Worth stating plainly because of how the bug presented: the runner
        // crashed mid-suite, relaunched, and reported "Test run with 0 tests
        // passed". A crash here does not look like a failure, it looks like
        // success with nothing in it.
        let onReadable: @Sendable () -> Void = {
            // One accept per event, then return to the source. A `while` loop
            // here would hold the queue for as long as a peer keeps
            // connecting.
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            defer { close(client) }
            guard let payload = Self.readPayload(from: client) else { return }
            Task { @MainActor in _ = handler(payload) }
        }
        source.setEventHandler(handler: onReadable)

        // The descriptor is closed by the CANCEL HANDLER, never by `stop()`
        // directly: a DispatchSource owns its file descriptor for as long as
        // it is live, and closing one out from under it is undefined.
        let onCancel: @Sendable () -> Void = { close(fd) }
        source.setCancelHandler(handler: onCancel)
        source.resume()

        listeningFD = fd
        acceptSource = source
    }

    func stop() {
        // Cancel only. The cancel handler installed in `start()` closes the
        // descriptor once libdispatch has actually stopped using it.
        acceptSource?.cancel()
        acceptSource = nil
        listeningFD = nil
        // Unlinked on the way out so the next launch binds cleanly, rather
        // than relying on the unlink in `start()` to clean up after us.
        unlink(url.path)
    }

    /// Reads one newline-terminated payload, refusing to buffer more than the
    /// cap.
    ///
    /// Reads one byte past `maxPayloadBytes` on purpose: that is the cheapest
    /// way to *know* a payload is oversized rather than to truncate one and
    /// hand policy something that looks valid. Nil means "nothing worth
    /// handing on" — an empty connection, a read error, or an oversized
    /// payload — and the connection is closed either way.
    private nonisolated static func readPayload(from client: Int32) -> Data? {
        let limit = SignalWire.maxPayloadBytes + 1
        var payload = Data()
        var byte = [UInt8](repeating: 0, count: 1)

        while payload.count < limit {
            let read = recv(client, &byte, 1, 0)
            if read <= 0 { break }              // peer closed, or an error
            if byte[0] == UInt8(ascii: "\n") { break }
            payload.append(byte[0])
        }

        if payload.isEmpty { return nil }
        // Over the cap: refused here rather than passed to policy, so an
        // oversized payload costs one byte of overshoot instead of whatever
        // the peer chose to send.
        if payload.count > SignalWire.maxPayloadBytes { return nil }
        return payload
    }
}

// `SignalSocketClient` used to live here. It now lives in `AinkradSignal`
// alongside `SignalSocketPath`, because `ainkrad notify` needs the identical
// connect-write-close and the identical path — and a second copy in the CLI
// would be free to drift from what this server actually accepts.
