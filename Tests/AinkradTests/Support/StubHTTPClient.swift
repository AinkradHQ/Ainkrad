import Foundation

@testable import Ainkrad

/// HTTPClient stub returning canned bytes per URL (or an error).
struct StubHTTPClient: HTTPClient {
    var responses: [URL: Result<Data, Error>]
    struct NoStub: Error {}
    func get(_ url: URL) async throws -> Data {
        switch responses[url] {
        case .success(let d): return d
        case .failure(let e): throw e
        case nil: throw NoStub()
        }
    }
}
