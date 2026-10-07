import Testing

@testable import AinkradDevHost

/// `LogTail` reads two sources through the SAME `stream(subsystem:)` surface:
/// an injected lifecycle-event stream (deterministic, what these tests
/// exercise) and a real `OSLogStore` tail (not unit-testable — no live
/// system log store in CI, no entitlement). Every test here injects BOTH the
/// lifecycle events AND a stub for the system-log side (an already-finished
/// empty stream), so the real `OSLogStore` is never touched and the merged
/// stream finishes deterministically once the injected event stream is
/// finished — no real sleeps, no unbounded await.
@Suite("LogTail")
struct LogTailTests {
    @Test("emits loaded, rejected, and reloaded lifecycle lines from injected events")
    func emitsLifecycleLines() async {
        let (events, continuation) = AsyncStream<LogTail.LifecycleEvent>.makeStream()
        let tail = LogTail(
            lifecycleEvents: events,
            readSystemLog: { _ in AsyncStream { $0.finish() } }
        )

        continuation.yield(.loaded("hello"))
        continuation.yield(.rejected(reason: "missing Info.plist"))
        continuation.yield(.reloaded)
        continuation.finish()

        var lines: [String] = []
        for await line in tail.stream(subsystem: "com.ainkrad.app") {
            lines.append(line)
        }

        #expect(lines == ["loaded: hello", "rejected: missing Info.plist", "reloaded"])
    }

    @Test("the rejected line contains the injected reason verbatim")
    func rejectedLineContainsReason() async {
        let (events, continuation) = AsyncStream<LogTail.LifecycleEvent>.makeStream()
        let tail = LogTail(
            lifecycleEvents: events,
            readSystemLog: { _ in AsyncStream { $0.finish() } }
        )

        continuation.yield(.rejected(reason: "metadata: unsupported apiVersion 5"))
        continuation.finish()

        var lines: [String] = []
        for await line in tail.stream(subsystem: "com.ainkrad.app") {
            lines.append(line)
        }

        #expect(lines.count == 1)
        #expect(lines[0].contains("metadata: unsupported apiVersion 5"))
    }

    @Test("line(for:) is a pure formatter, independent of streaming")
    func lineFormatsEachEvent() {
        #expect(LogTail.line(for: .loaded("id")) == "loaded: id")
        #expect(LogTail.line(for: .rejected(reason: "bad")) == "rejected: bad")
        #expect(LogTail.line(for: .reloaded) == "reloaded")
    }
}
