import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/LSP/LSPFraming.swift
import Foundation

/// Content-Length framing (LSP's wire format, RFC-7230-style header block) —
/// unlike MCP's newline-delimited JSON, a message is `Content-Length: <N>\r\n\r\n`
/// followed by exactly `N` **bytes** (not characters) of UTF-8 JSON body. `N`
/// must be measured on the encoded `Data`, never on `String.count`, or a body
/// with multi-byte UTF-8 (non-ASCII diagnostics/messages) would frame wrong.
enum LSPFraming {
    static func encode(_ message: JSONValue) -> Data {
        let obj = message.toFoundationObject()
        let body = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
        let header = "Content-Length: \(body.count)\r\n\r\n"
        var framed = Data(header.utf8)
        framed.append(body)
        return framed
    }
}

/// Stateful byte-chunk reassembler for Content-Length-framed messages. Only
/// ever touched from a single serial callback (mirrors `LineParser` in
/// `StdioTransport`), so the mutable buffer is safe without a lock —
/// `@unchecked Sendable` only tells the compiler that invariant holds.
///
/// Handles, without ever crashing or looping forever on `push`:
/// - multiple complete messages arriving in one chunk (loop until no full
///   frame remains),
/// - a message split across chunks (buffer and wait for more bytes — both
///   the header and the body can be split),
/// - a malformed/garbage header — never a valid `Content-Length` line — which
///   is discarded up through the first `\r\n\r\n` so the parser resyncs on
///   whatever well-formed frame follows, instead of wedging on bad input.
final class LSPFrameParser: @unchecked Sendable {
    private var buffer = Data()

    func push(_ chunk: Data) -> [JSONValue] {
        buffer.append(chunk)
        var messages: [JSONValue] = []
        while true {
            guard let separatorRange = buffer.range(of: Self.headerSeparator) else {
                // No full header yet (or pure noise with no CRLFCRLF at all) —
                // wait for more bytes rather than spinning.
                break
            }
            let headerData = buffer[buffer.startIndex..<separatorRange.lowerBound]
            let headerText = String(decoding: headerData, as: UTF8.self)
            guard let contentLength = Self.contentLength(fromHeader: headerText) else {
                // Malformed header: never a valid frame, so discard it (up
                // through the separator) and resync on the next one.
                buffer.removeSubrange(buffer.startIndex..<separatorRange.upperBound)
                continue
            }
            let bodyStart = separatorRange.upperBound
            let bodyEnd = buffer.index(bodyStart, offsetBy: contentLength, limitedBy: buffer.endIndex)
            guard let bodyEnd else {
                // Body not fully arrived yet — leave the buffer (header
                // included) intact and wait for the next chunk.
                break
            }
            let bodyData = buffer[bodyStart..<bodyEnd]
            buffer.removeSubrange(buffer.startIndex..<bodyEnd)
            if let value = JSONValue.parse(String(decoding: bodyData, as: UTF8.self)) {
                messages.append(value)
            }
            // Non-JSON body bytes (shouldn't happen for a spec-conformant
            // server) are dropped, never fatal — mirrors MCP's LineParser.
        }
        return messages
    }

    private static let headerSeparator = Data("\r\n\r\n".utf8)

    /// Parses the (possibly multi-line) header block for a `Content-Length`
    /// entry. Header names are case-insensitive per RFC 7230; LSP servers
    /// only ever send `Content-Length` (and optionally `Content-Type`, which
    /// is ignored here).
    private static func contentLength(fromHeader header: String) -> Int? {
        for line in header.split(separator: "\r\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                String(parts[0]).caseInsensitiveCompare("Content-Length") == .orderedSame
            else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            if let length = Int(value), length >= 0 { return length }
        }
        return nil
    }
}
