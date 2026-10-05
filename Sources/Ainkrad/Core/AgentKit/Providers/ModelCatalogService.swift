// Sources/Ainkrad/Core/AgentKit/Providers/ModelCatalogService.swift
import Foundation

/// Why a connection probe failed.
///
/// Derived from the ACTUAL response — the HTTP status code, or which branch of
/// the probe produced the failure — and NEVER by matching on
/// `ConnectionTestResult.message`. Display copy is rewritten routinely; a
/// classification that silently changes with it is a bug waiting to happen, so
/// the distinction is carried out of the probe as a value instead of being
/// reconstructed later from prose.
///
/// The split that matters to callers is `allowsDeferral`: whose fault is this?
/// A wrong key or a malformed base URL is the user's to fix, and fixing it is
/// the point of asking. A 429, a 5xx, a 404 or an unreachable host is not —
/// blocking the user on those achieves nothing, because there is nothing for
/// them to do. The predicate is named for the DECISION it drives rather than for
/// "temporary", because not every case it admits is temporary: a 404 is a
/// permanent fact about an endpoint and still must not lock anyone out.
enum ConnectionFailure: Equatable, Sendable {
    /// The base URL could not even be turned into a request.
    case invalidBaseURL
    /// 401 / 403 — the credential was rejected.
    case unauthorized(status: Int)
    /// Any other 4xx — a request the provider refused. Says something about the
    /// REQUEST (a 400 is malformed input), which is the user's to fix.
    case rejected(status: Int)
    /// 404 — the endpoint has no `/models` route.
    ///
    /// Deliberately NOT grouped with `rejected`: a healthy OpenAI-compatible
    /// server (Ollama, LM Studio, a thin proxy) that simply does not serve model
    /// discovery answers 404, and 404 says nothing whatsoever about the
    /// credential. The cost of being wrong here is asymmetric — a wrongly
    /// blocked user is locked out of the app, a wrongly deferrable one is
    /// offered a button they need not press — so the benefit of the doubt goes
    /// to letting them past.
    case notFound(status: Int)
    /// 429 — rate limited upstream.
    case rateLimited(status: Int)
    /// 5xx — the provider is having trouble.
    case serverError(status: Int)
    /// Transport failure: offline, DNS, timeout, connection refused.
    case unreachable

    /// True when the failure belongs to the provider or the network rather than
    /// to the user. This is the ONLY predicate the setup wizard consults when
    /// deciding whether to offer "Set this up later".
    var allowsDeferral: Bool {
        switch self {
        case .notFound, .rateLimited, .serverError, .unreachable:
            return true
        case .invalidBaseURL, .unauthorized, .rejected:
            return false
        }
    }

    /// The single place an HTTP status becomes a classification.
    ///
    /// Shared by the model-catalog probe and by `ClaudeOAuthLoginController`'s
    /// token-endpoint failures, so the two subsystems cannot drift into
    /// disagreeing about whether the same status is the user's fault.
    static func forHTTP(status: Int) -> ConnectionFailure {
        switch status {
        case 401, 403: return .unauthorized(status: status)
        case 404: return .notFound(status: status)
        case 429: return .rateLimited(status: status)
        case 500...599: return .serverError(status: status)
        default: return .rejected(status: status)
        }
    }
}

struct ConnectionTestResult: Equatable, Sendable {
    let ok: Bool
    let message: String  // user-facing; NEVER contains the API key
    /// Machine-readable reason, `nil` exactly when `ok`. Callers classify from
    /// this — never from `message`.
    let failure: ConnectionFailure?

    init(ok: Bool, message: String, failure: ConnectionFailure? = nil) {
        self.ok = ok
        self.message = message
        self.failure = failure
    }
}

/// Fetches a provider's available model ids (live, with a curated fallback),
/// and doubles as a connection health check. All failures are reported with
/// the API key redacted.
@MainActor
final class ModelCatalogService {
    private let http: DataHTTPClient

    init(http: DataHTTPClient) {
        self.http = http
    }

    func models(kind: ProviderKind, baseURL: String, credential: ProviderCredential, curatedFallback: [String]) async
        -> [String]
    {
        await modelsResult(kind: kind, baseURL: baseURL, credential: credential, curatedFallback: curatedFallback)
            .models
    }

    /// Same as `models(...)`, but also signals whether the returned list was
    /// genuinely fetched live (`isLive == true`) or is the curated fallback
    /// returned due to an invalid request, non-2xx response, transport error,
    /// or empty parse (`isLive == false`). Callers should only treat the list
    /// as authoritative (e.g. for reconciling a selected model) when `isLive`.
    func modelsResult(kind: ProviderKind, baseURL: String, credential: ProviderCredential, curatedFallback: [String])
        async -> (models: [String], isLive: Bool)
    {
        guard let request = Self.listRequest(kind: kind, baseURL: baseURL, credential: credential) else {
            return (curatedFallback, false)
        }
        do {
            let (data, response) = try await http.data(for: request)
            guard (200...299).contains(response.statusCode) else { return (curatedFallback, false) }
            // A well-formed response is authoritative even when it lists zero models
            // (the provider genuinely has none) — return it live so callers show the
            // real (possibly empty) set rather than the curated fallback. Only a
            // parse failure (nil) falls back to curated.
            guard let parsed = Self.parseModels(kind: kind, data: data) else { return (curatedFallback, false) }
            return (parsed, true)
        } catch {
            return (curatedFallback, false)
        }
    }

    func test(kind: ProviderKind, baseURL: String, credential: ProviderCredential) async -> ConnectionTestResult {
        guard let request = Self.listRequest(kind: kind, baseURL: baseURL, credential: credential) else {
            return ConnectionTestResult(
                ok: false, message: "Invalid base URL",
                failure: .invalidBaseURL)
        }
        do {
            let (data, response) = try await http.data(for: request)
            if (200...299).contains(response.statusCode) {
                let count = (Self.parseModels(kind: kind, data: data) ?? []).count
                return ConnectionTestResult(ok: true, message: count > 0 ? "Connected · \(count) models" : "Connected")
            }
            // Body is the server's response — never contains the request key —
            // but be defensive and only surface a parsed message field.
            //
            // The classification comes from `response.statusCode`, NOT from the
            // message built on the next line: that message may be the provider's
            // own prose, which we neither control nor can parse reliably.
            let failure = ConnectionFailure.forHTTP(status: response.statusCode)
            let message = Self.errorMessage(data: data) ?? "HTTP \(response.statusCode)"
            return ConnectionTestResult(ok: false, message: message, failure: failure)
        } catch {
            return ConnectionTestResult(
                ok: false, message: "Could not reach endpoint",
                failure: .unreachable)
        }
    }

    // MARK: - Request/parse per kind

    private static func trim(_ baseURL: String) -> String {
        baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
    }

    /// Builds the `/models` discovery request. Auth depends on BOTH the provider
    /// kind and the credential: a subscription (`.oauth`) connection is keyless, so
    /// it authenticates with `authorization: Bearer <token>` — the same header the
    /// live `/v1/messages` OAuth path uses — NOT an (empty) `x-api-key`, which would
    /// 401 and silently drop discovery back to the curated fallback.
    private static func listRequest(kind: ProviderKind, baseURL: String, credential: ProviderCredential) -> URLRequest?
    {
        let base = trim(baseURL)
        guard let url = URL(string: base + "/models") else { return nil }
        var r = URLRequest(url: url)
        switch kind {
        case .openAICompatible:
            switch credential {
            case .apiKey(let key): if !key.isEmpty { r.setValue("Bearer \(key)", forHTTPHeaderField: "authorization") }
            case .oauth(let token): r.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "authorization")
            }
        case .claude:
            r.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            switch credential {
            case .apiKey(let key): r.setValue(key, forHTTPHeaderField: "x-api-key")
            case .oauth(let token): r.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "authorization")
            }
        case .gemini:
            switch credential {
            case .apiKey(let key): r.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            case .oauth(let token): r.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "authorization")
            }
        }
        return r
    }

    /// Returns `nil` when the body couldn't be parsed at all (unexpected shape),
    /// distinguished from a well-formed response that genuinely lists zero models
    /// (`[]`). Callers use that difference to decide between a curated fallback
    /// (parse failure — we don't know) and an authoritative empty list (the
    /// provider really has no models, e.g. an Ollama with nothing pulled).
    private static func parseModels(kind: ProviderKind, data: Data) -> [String]? {
        switch kind {
        case .openAICompatible, .claude:
            struct List: Decodable {
                struct Item: Decodable { let id: String }
                let data: [Item]?
            }
            guard let list = try? JSONDecoder().decode(List.self, from: data) else { return nil }
            return list.data?.map(\.id) ?? []
        case .gemini:
            struct List: Decodable {
                struct Item: Decodable { let name: String }
                let models: [Item]?
            }
            guard let list = try? JSONDecoder().decode(List.self, from: data) else { return nil }
            return list.models?.map {
                $0.name.hasPrefix("models/") ? String($0.name.dropFirst("models/".count)) : $0.name
            } ?? []
        }
    }

    private static func errorMessage(data: Data) -> String? {
        struct Envelope: Decodable {
            struct E: Decodable { let message: String? }
            let error: E?
        }
        return (try? JSONDecoder().decode(Envelope.self, from: data))?.error?.message
    }
}
