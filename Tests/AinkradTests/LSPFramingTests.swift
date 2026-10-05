import AinkradHostRuntime
// Tests/AinkradTests/LSPFramingTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("LSP framing")
struct LSPFramingTests {
    @Test func encodesContentLengthHeader() {
        let data = LSPFraming.encode(.object(["jsonrpc": .string("2.0")]))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.hasPrefix("Content-Length: "))
        #expect(text.contains("\r\n\r\n"))
    }

    @Test func headerByteCountMatchesUTF8BodyBytes() {
        // A body containing multi-byte UTF-8 (e.g. emoji/non-ASCII) must be
        // counted in BYTES, not characters, or the parser under/over-reads.
        let data = LSPFraming.encode(.object(["message": .string("héllo 🎉")]))
        let text = String(decoding: data, as: UTF8.self)
        guard let range = text.range(of: "\r\n\r\n") else {
            Issue.record("missing header/body separator")
            return
        }
        let header = text[text.startIndex..<range.lowerBound]
        guard let lengthString = header.split(separator: " ").last,
            let declaredLength = Int(lengthString)
        else {
            Issue.record("could not parse Content-Length header")
            return
        }
        let bodyStart = text.index(range.upperBound, offsetBy: 0)
        let bodyBytes = Data(text[bodyStart...].utf8)
        #expect(declaredLength == bodyBytes.count)
    }

    @Test func parsesFramedMessageAcrossChunks() {
        let payload = LSPFraming.encode(.object(["id": .string("1"), "result": .object([:])]))
        let parser = LSPFrameParser()
        let half = payload.count / 2
        var out = parser.push(payload.prefix(half))
        #expect(out.isEmpty)
        out += parser.push(payload.suffix(from: payload.index(payload.startIndex, offsetBy: half)))
        #expect(out.first?["id"]?.stringValue == "1")
    }

    @Test func parsesMultipleMessagesInOneChunk() {
        let first = LSPFraming.encode(.object(["id": .string("1")]))
        let second = LSPFraming.encode(.object(["id": .string("2")]))
        let parser = LSPFrameParser()
        let out = parser.push(first + second)
        #expect(out.count == 2)
        #expect(out[0]["id"]?.stringValue == "1")
        #expect(out[1]["id"]?.stringValue == "2")
    }

    @Test func garbageHeaderNeverCrashesAndIsSkipped() {
        // Malformed header bytes (no valid "Content-Length:" line, and never
        // resolving to a real frame) must not crash — and once a well-formed
        // frame follows, the parser recovers and yields it.
        let garbage = Data("not-a-valid-header\r\n\r\n".utf8)
        let good = LSPFraming.encode(.object(["id": .string("42")]))
        let parser = LSPFrameParser()
        let out = parser.push(garbage + good)
        #expect(out.count == 1)
        #expect(out.first?["id"]?.stringValue == "42")
    }

    @Test func garbageHeaderWithNoTrailingSeparatorNeverCrashes() {
        // Pure noise with no CRLFCRLF at all — parser must just buffer it,
        // not crash, and not spin/loop forever on `push`.
        let parser = LSPFrameParser()
        let out = parser.push(Data("garbage garbage garbage".utf8))
        #expect(out.isEmpty)
    }

    /// Real spawn + Content-Length framing round-trip via a `cat` echo (mirrors
    /// Task 3's stdio test: framed bytes in → same framed bytes out → parsed).
    @Test func stdioTransportEchoesFramedMessage() async throws {
        let t = LSPStdioTransport(command: "/bin/cat", args: [], env: [:])
        try await t.start()
        defer { Task { await t.stop() } }
        var iterator = t.incoming().makeAsyncIterator()
        try await t.send(
            .object([
                "jsonrpc": .string("2.0"), "id": .string("1"),
                "method": .string("initialize"), "params": .object([:]),
            ]))
        let received = try await iterator.next()
        #expect(received?["id"]?.stringValue == "1")
    }

    @Test func stdioTransportWriteToDeadServerThrows() async throws {
        // Mirrors the MCP StdioTransport dead-server test: spawn something
        // that exits immediately, wait for it to die, then confirm `send`
        // throws a catchable error instead of crashing the host via SIGPIPE.
        let t = LSPStdioTransport(command: "/bin/cat", args: [], env: [:])
        try await t.start()
        await t.stop()
        await #expect(throws: (any Error).self) {
            try await t.send(.object(["id": .string("1")]))
        }
    }

    @Test func lspDiagnosticDecodesFromWireShape() {
        let wire = JSONValue.object([
            "range": .object([
                "start": .object(["line": .number(3), "character": .number(7)])
            ]),
            "severity": .number(1),
            "message": .string("unexpected token"),
        ])
        let diagnostic = LSPDiagnostic.decode(wire)
        #expect(
            diagnostic
                == LSPDiagnostic(
                    line: 3, character: 7, severity: 1,
                    message: "unexpected token"))
    }

    @Test func lspTextEditDecodesFromWireShape() {
        let wire = JSONValue.object([
            "range": .object([
                "start": .object(["line": .number(0), "character": .number(0)]),
                "end": .object(["line": .number(0), "character": .number(5)]),
            ]),
            "newText": .string("hello"),
        ])
        let edit = LSPTextEdit.decode(wire)
        #expect(
            edit
                == LSPTextEdit(
                    startLine: 0, startCharacter: 0, endLine: 0,
                    endCharacter: 5, newText: "hello"))
    }
}
