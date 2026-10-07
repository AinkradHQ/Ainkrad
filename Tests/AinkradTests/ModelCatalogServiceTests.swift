import Foundation
// Tests/AinkradTests/ModelCatalogServiceTests.swift
import Testing

@testable import Ainkrad

@MainActor
@Suite("ModelCatalogService")
struct ModelCatalogServiceTests {
    struct StubDataHTTPClient: DataHTTPClient {
        let status: Int
        let body: String
        let captured: (@Sendable (URLRequest) -> Void)?
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            captured?(request)
            let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), resp)
        }
    }

    @Test("parses OpenAI-compatible /models list")
    func openAIList() async throws {
        let stub = StubDataHTTPClient(
            status: 200,
            body: "{\"data\":[{\"id\":\"gpt-5\"},{\"id\":\"gpt-5-mini\"}]}", captured: nil)
        let svc = ModelCatalogService(http: stub)
        let models = await svc.models(
            kind: .openAICompatible, baseURL: "https://api.openai.com/v1", credential: .apiKey("k"),
            curatedFallback: ["fallback"])
        #expect(models == ["gpt-5", "gpt-5-mini"])
    }

    @Test("parses Gemini models list and strips the models/ prefix")
    func geminiList() async throws {
        let stub = StubDataHTTPClient(
            status: 200,
            body: "{\"models\":[{\"name\":\"models/gemini-2.5-pro\"}]}", captured: nil)
        let svc = ModelCatalogService(http: stub)
        let models = await svc.models(
            kind: .gemini, baseURL: "https://x/v1beta", credential: .apiKey("k"), curatedFallback: [])
        #expect(models == ["gemini-2.5-pro"])
    }

    @Test("falls back to curated list on failure")
    func fallback() async throws {
        let stub = StubDataHTTPClient(status: 500, body: "boom", captured: nil)
        let svc = ModelCatalogService(http: stub)
        let models = await svc.models(
            kind: .openAICompatible, baseURL: "https://x/v1", credential: .apiKey("k"), curatedFallback: ["a", "b"])
        #expect(models == ["a", "b"])
    }

    @Test("modelsResult signals isLive == false on a 500 fallback")
    func modelsResultFallbackIsNotLive() async throws {
        let stub = StubDataHTTPClient(status: 500, body: "boom", captured: nil)
        let svc = ModelCatalogService(http: stub)
        let result = await svc.modelsResult(
            kind: .openAICompatible, baseURL: "https://x/v1", credential: .apiKey("k"), curatedFallback: ["a", "b"])
        #expect(result.models == ["a", "b"])
        #expect(result.isLive == false)
    }

    @Test("a well-formed but EMPTY list is authoritative (live, no curated fallback)")
    func modelsResultEmptyListIsAuthoritative() async throws {
        // e.g. an Ollama with nothing pulled: `{"data":[]}` means the provider
        // genuinely has zero models — show that, NOT the hardcoded curated list.
        let stub = StubDataHTTPClient(status: 200, body: "{\"data\":[]}", captured: nil)
        let svc = ModelCatalogService(http: stub)
        let result = await svc.modelsResult(
            kind: .openAICompatible, baseURL: "https://x/v1", credential: .apiKey("k"),
            curatedFallback: ["llama3.2", "qwen2.5-coder"])
        #expect(result.models == [])  // NOT the curated fallback
        #expect(result.isLive == true)  // authoritative
    }

    @Test("an UNPARSEABLE 200 body falls back to curated (isLive == false)")
    func modelsResultUnparseableFallsBackToCurated() async throws {
        // A 2xx whose body we can't decode at all — we don't know the real set,
        // so the curated fallback is the honest choice (distinct from empty).
        let stub = StubDataHTTPClient(status: 200, body: "not json at all", captured: nil)
        let svc = ModelCatalogService(http: stub)
        let result = await svc.modelsResult(
            kind: .openAICompatible, baseURL: "https://x/v1", credential: .apiKey("k"), curatedFallback: ["a", "b"])
        #expect(result.models == ["a", "b"])
        #expect(result.isLive == false)
    }

    @Test("modelsResult signals isLive == true on a successful fetch")
    func modelsResultLiveFetchIsLive() async throws {
        let stub = StubDataHTTPClient(
            status: 200,
            body: "{\"data\":[{\"id\":\"gpt-5\"},{\"id\":\"gpt-5-mini\"}]}", captured: nil)
        let svc = ModelCatalogService(http: stub)
        let result = await svc.modelsResult(
            kind: .openAICompatible, baseURL: "https://api.openai.com/v1", credential: .apiKey("k"),
            curatedFallback: ["fallback"])
        #expect(result.models == ["gpt-5", "gpt-5-mini"])
        #expect(result.isLive == true)
    }

    @Test("test() returns ok on 200")
    func testOK() async throws {
        let stub = StubDataHTTPClient(status: 200, body: "{\"data\":[{\"id\":\"m\"}]}", captured: nil)
        let svc = ModelCatalogService(http: stub)
        #expect(await svc.test(kind: .openAICompatible, baseURL: "https://x/v1", credential: .apiKey("k")).ok == true)
    }

    @Test("test() failure never leaks the key")
    func testFailRedaction() async throws {
        let stub = StubDataHTTPClient(status: 401, body: "{\"error\":{\"message\":\"unauthorized\"}}", captured: nil)
        let svc = ModelCatalogService(http: stub)
        let result = await svc.test(kind: .openAICompatible, baseURL: "https://x/v1", credential: .apiKey("sk-secret"))
        #expect(result.ok == false)
        #expect(!result.message.contains("sk-secret"))
    }

    // MARK: - Subscription (OAuth) credential — the fix for keyless discovery

    private static func oauthToken(_ access: String) -> OAuthToken {
        OAuthToken(
            accessToken: access, refreshToken: "r",
            expiresAt: Date(timeIntervalSince1970: 4_000_000_000), scopes: [])
    }

    /// Sendable box so the `@Sendable` capture closure can record the request.
    private final class RequestBox: @unchecked Sendable { var request: URLRequest? }

    @Test("claude + OAuth authenticates discovery with a Bearer token, NOT x-api-key")
    func claudeOAuthUsesBearer() async throws {
        let box = RequestBox()
        let stub = StubDataHTTPClient(
            status: 200, body: "{\"data\":[{\"id\":\"claude-sonnet-5\"}]}",
            captured: { box.request = $0 })
        let svc = ModelCatalogService(http: stub)
        let result = await svc.modelsResult(
            kind: .claude, baseURL: "https://api.anthropic.com/v1",
            credential: .oauth(Self.oauthToken("tok-123")),
            curatedFallback: ["claude-opus-4-8"])
        // Live list is used, not the curated fallback.
        #expect(result.models == ["claude-sonnet-5"])
        #expect(result.isLive == true)
        // Authenticated as a subscription: Bearer set, no (empty) x-api-key.
        #expect(box.request?.value(forHTTPHeaderField: "authorization") == "Bearer tok-123")
        #expect(box.request?.value(forHTTPHeaderField: "x-api-key") == nil)
    }

    @Test("claude + API key still uses x-api-key, not Bearer")
    func claudeAPIKeyUsesXAPIKey() async throws {
        let box = RequestBox()
        let stub = StubDataHTTPClient(
            status: 200, body: "{\"data\":[{\"id\":\"m\"}]}",
            captured: { box.request = $0 })
        let svc = ModelCatalogService(http: stub)
        _ = await svc.modelsResult(
            kind: .claude, baseURL: "https://api.anthropic.com/v1",
            credential: .apiKey("sk-ant"), curatedFallback: [])
        #expect(box.request?.value(forHTTPHeaderField: "x-api-key") == "sk-ant")
        #expect(box.request?.value(forHTTPHeaderField: "authorization") == nil)
    }

    // MARK: - Failure classification (task 8)

    struct ThrowingDataHTTPClient: DataHTTPClient {
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            throw URLError(.cannotConnectToHost)
        }
    }

    /// The classification comes from `response.statusCode`, so it holds even when
    /// the provider ALSO returns prose that says something else entirely. This is
    /// the test that would fail if anyone reintroduced string matching: the body
    /// here says "invalid api key" on a 429.
    @Test("a 429 classifies as rate-limited from the STATUS, not the body text")
    func rateLimitedIsClassifiedFromStatus() async {
        let stub = StubDataHTTPClient(
            status: 429,
            body: "{\"error\":{\"type\":\"rate_limit_error\",\"message\":\"invalid api key\"}}",
            captured: nil)
        let result = await ModelCatalogService(http: stub)
            .test(kind: .claude, baseURL: "https://x/v1", credential: .apiKey("k"))
        #expect(!result.ok)
        #expect(result.failure == .rateLimited(status: 429))
        #expect(result.failure?.allowsDeferral == true)
        // The display copy is the provider's own prose; the verdict ignored it.
        #expect(result.message == "invalid api key")
    }

    @Test("401 and 403 classify as unauthorized and are NOT transient")
    func unauthorizedIsNotTransient() async {
        for status in [401, 403] {
            let stub = StubDataHTTPClient(status: status, body: "{}", captured: nil)
            let result = await ModelCatalogService(http: stub)
                .test(kind: .claude, baseURL: "https://x/v1", credential: .apiKey("bad"))
            #expect(result.failure == .unauthorized(status: status))
            #expect(result.failure?.allowsDeferral == false)
        }
    }

    @Test("5xx classifies as a server error and IS transient")
    func serverErrorIsTransient() async {
        for status in [500, 502, 503] {
            let stub = StubDataHTTPClient(status: status, body: "boom", captured: nil)
            let result = await ModelCatalogService(http: stub)
                .test(kind: .openAICompatible, baseURL: "https://x/v1", credential: .apiKey("k"))
            #expect(result.failure == .serverError(status: status))
            #expect(result.failure?.allowsDeferral == true)
        }
    }

    @Test("a transport failure classifies as unreachable and IS transient")
    func unreachableIsTransient() async {
        let result = await ModelCatalogService(http: ThrowingDataHTTPClient())
            .test(kind: .openAICompatible, baseURL: "https://x/v1", credential: .apiKey("k"))
        #expect(result.failure == .unreachable)
        #expect(result.failure?.allowsDeferral == true)
    }

    /// A base URL that cannot even become a request is the user's to fix — the
    /// step blocking on it is the step doing its job.
    @Test("a malformed base URL classifies as invalidBaseURL and is NOT transient")
    func invalidBaseURLIsNotTransient() async {
        let stub = StubDataHTTPClient(status: 200, body: "{}", captured: nil)
        let result = await ModelCatalogService(http: stub)
            .test(kind: .openAICompatible, baseURL: "https://[not-a-host", credential: .apiKey("k"))
        #expect(result.failure == .invalidBaseURL)
        #expect(result.failure?.allowsDeferral == false)
    }

    @Test("a successful probe carries no failure at all")
    func successCarriesNoFailure() async {
        let stub = StubDataHTTPClient(status: 200, body: "{\"data\":[{\"id\":\"m\"}]}", captured: nil)
        let result = await ModelCatalogService(http: stub)
            .test(kind: .openAICompatible, baseURL: "https://x/v1", credential: .apiKey("k"))
        #expect(result.ok)
        #expect(result.failure == nil)
    }

    /// A healthy OpenAI-compatible server that simply does not serve model
    /// discovery (Ollama, LM Studio, a thin proxy) answers 404 — which says
    /// nothing about the credential and must not lock the user out. A 400 DOES
    /// say something about the request, so it still blocks.
    @Test("404 does not block; 400 still does")
    func notFoundDoesNotBlock() async {
        let notFound = await ModelCatalogService(http: StubDataHTTPClient(status: 404, body: "", captured: nil))
            .test(kind: .openAICompatible, baseURL: "https://x/v1", credential: .apiKey("k"))
        #expect(notFound.failure == .notFound(status: 404))
        #expect(notFound.failure?.allowsDeferral == true)

        let badRequest = await ModelCatalogService(http: StubDataHTTPClient(status: 400, body: "", captured: nil))
            .test(kind: .openAICompatible, baseURL: "https://x/v1", credential: .apiKey("k"))
        #expect(badRequest.failure == .rejected(status: 400))
        #expect(badRequest.failure?.allowsDeferral == false)
    }
}
