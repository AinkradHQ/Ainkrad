// Tests/AinkradTests/Support/ArrayTokenTransport.swift
import Foundation

@testable import Ainkrad

/// Shared `OAuthTokenTransport` test double that replays a fixed queue of
/// canned (body, status) responses in order — used wherever a test needs to
/// simulate the OAuth token endpoint without touching the network.
final class ArrayTokenTransport: OAuthTokenTransport, @unchecked Sendable {
    private var responses: [(Data, Int)]
    private(set) var requests: [URLRequest] = []

    init(responses: [(Data, Int)]) {
        self.responses = responses
    }

    func post(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (data, status) = responses.removeFirst()
        let resp = HTTPURLResponse(
            url: request.url!, statusCode: status,
            httpVersion: nil, headerFields: nil)!
        return (data, resp)
    }
}
