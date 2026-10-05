import Foundation

/// A `DataHTTPClient` for `web_fetch` that re-validates EVERY redirect hop
/// through `WebURLValidator` and refuses to follow a redirect whose target is
/// non-http(s) or a private/loopback/link-local host. Refusing returns the 3xx
/// response unfollowed, which `WebFetchTool`'s non-2xx guard then rejects — so
/// the outbound request to an internal host is never dispatched. Closes the
/// auto-redirect SSRF vector that the boundary check on the initial URL alone
/// cannot (URLSession.shared auto-follows redirects with no per-hop check).
final class RedirectValidatingHTTPClient: NSObject, DataHTTPClient, URLSessionTaskDelegate, @unchecked Sendable {
    // Written exactly once in `init` (before any concurrent `data(for:)` call),
    // read-only thereafter — so `nonisolated(unsafe)` is sound and avoids the
    // unsynchronized `lazy var` init race under concurrent web_fetch calls
    // (e.g. multiple subagents). `self` is needed as the delegate, so the
    // session can't be a stored-property initializer expression.
    private nonisolated(unsafe) var session: URLSession!

    override init() {
        super.init()
        session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if let url = request.url, Self.isSafeRedirectTarget(url) {
            completionHandler(request)  // public http(s) target — follow, re-validated
        } else {
            completionHandler(nil)  // unsafe target — stop; 3xx flows back, tool rejects non-2xx
        }
    }

    /// Pure decision seam (unit-tested): a redirect is safe to follow only if
    /// its target passes the same boundary check applied to the initial URL.
    static func isSafeRedirectTarget(_ url: URL) -> Bool {
        (try? WebURLValidator.validate(url.absoluteString)) != nil
    }
}
