import Foundation
import Testing

@testable import Ainkrad

@Suite("WebFetchTool")
@MainActor
struct WebFetchToolTests {
    private struct StubHTTP: DataHTTPClient {
        let body: Data
        let status: Int
        let contentType: String
        var finalURL: URL? = nil
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let resp = HTTPURLResponse(
                url: finalURL ?? request.url!, statusCode: status,
                httpVersion: nil, headerFields: ["Content-Type": contentType])!
            return (body, resp)
        }
    }

    @Test func fetchesAndStripsHTML() async throws {
        let http = StubHTTP(body: Data("<p>Hello <b>web</b></p>".utf8), status: 200, contentType: "text/html")
        let r = try await WebFetchTool(http: http).execute(.object(["url": .string("https://example.com")]))
        #expect(!r.isError)
        #expect(r.content.contains("Hello"))
        #expect(!r.content.contains("<p>"))
    }
    @Test func refusesPrivateHost() async {
        let http = StubHTTP(body: Data(), status: 200, contentType: "text/html")
        await #expect(throws: ToolError.self) {
            _ = try await WebFetchTool(http: http).execute(.object(["url": .string("http://127.0.0.1")]))
        }
    }
    @Test func rejectsNon2xx() async {
        let http = StubHTTP(body: Data("nope".utf8), status: 404, contentType: "text/html")
        await #expect(throws: ToolError.self) {
            _ = try await WebFetchTool(http: http).execute(.object(["url": .string("https://example.com")]))
        }
    }
    @Test func rejectsUnsupportedContentType() async {
        let http = StubHTTP(body: Data([0x1, 0x2]), status: 200, contentType: "image/png")
        await #expect(throws: ToolError.self) {
            _ = try await WebFetchTool(http: http).execute(.object(["url": .string("https://example.com")]))
        }
    }
    @Test func refusesWhenFinalURLIsPrivate() async {
        let http = StubHTTP(
            body: Data("<p>x</p>".utf8), status: 200,
            contentType: "text/html",
            finalURL: URL(string: "http://169.254.169.254/latest")!)
        await #expect(throws: ToolError.self) {
            _ = try await WebFetchTool(http: http).execute(.object(["url": .string("https://example.com")]))
        }
    }
    @Test func permissionIsRead() {
        #expect(WebFetchTool(http: StubHTTP(body: Data(), status: 200, contentType: "text/html")).permission == .read)
    }
}
