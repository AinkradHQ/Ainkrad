// Tests/AinkradTests/Support/StubDataHTTPClient.swift
import Foundation

@testable import Ainkrad

/// Shared `DataHTTPClient` test double that returns a canned status/body —
/// used wherever a test needs to simulate a live HTTP model-listing endpoint
/// without touching the network.
struct StubDataHTTPClient: DataHTTPClient {
    let status: Int
    let body: Data

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (body, resp)
    }
}

/// Shared `DataHTTPClient` test double that always throws — simulates a
/// connection-refused/timeout from a local server that isn't running.
struct ThrowingDataHTTPClient: DataHTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(.cannotConnectToHost)
    }
}
