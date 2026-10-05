import Foundation
import Testing

@testable import Ainkrad

@Suite("SSEParser")
struct SSEParserTests {
    // Turn a list of byte-chunks into the upstream stream the parser consumes.
    private func stream(_ chunks: [String]) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { cont in
            for c in chunks { cont.yield(Data(c.utf8)) }
            cont.finish()
        }
    }

    @Test("reassembles data events split across arbitrary chunk boundaries")
    func reassembles() async throws {
        // "data: hello\n\n" and "data: world\n\n" split mid-token.
        let up = stream(["data: hel", "lo\n\ndata: wor", "ld\n\n"])
        var out: [String] = []
        for try await e in SSEParser.events(from: up) { out.append(e) }
        #expect(out == ["hello", "world"])
    }

    @Test("ignores comments and blank keep-alives; stops at [DONE]")
    func ignoresAndStops() async throws {
        let up = stream([": keep-alive\n\n", "data: a\n\n", "data: [DONE]\n\n", "data: b\n\n"])
        var out: [String] = []
        for try await e in SSEParser.events(from: up) { out.append(e) }
        #expect(out == ["a"])
    }

    @Test("joins multi-line data payloads with newlines")
    func multiLine() async throws {
        let up = stream(["data: line1\ndata: line2\n\n"])
        var out: [String] = []
        for try await e in SSEParser.events(from: up) { out.append(e) }
        #expect(out == ["line1\nline2"])
    }
}
