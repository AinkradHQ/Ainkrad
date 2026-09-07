// Sources/Ainkrad/Core/AgentKit/Providers/GeminiProvider.swift
import Foundation
import AinkradHostRuntime

/// `LLMProvider` conformer for Google's native Gemini API
/// (`POST {baseURL}/models/{model}:streamGenerateContent?alt=sse`). Gemini has
/// no per-call tool id, so the function NAME is used as the tool-call id and to
/// match `functionResponse` parts back to their call.
struct GeminiProvider: LLMProvider {
    private let http: StreamingHTTPClient
    private let baseURL: String

    init(http: StreamingHTTPClient, baseURL: String) {
        self.http = http
        self.baseURL = baseURL
    }

    func send(
        messages: [AgentMessage],
        system: String,
        tools: [AgentToolSchema],
        model: AgentModelConfig,
        credential: ProviderCredential
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        let apiKey: String = { if case let .apiKey(k) = credential { return k } else { return "" } }()
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = Self.makeRequest(baseURL: baseURL, messages: messages, system: system,
                                                   tools: tools, model: model, apiKey: apiKey)
                    let bytes = try await http.post(request)
                    var finishReason: String?
                    var latestUsage: TokenUsage?

                    for try await payload in SSEParser.events(from: bytes) {
                        guard let data = payload.data(using: .utf8) else { continue }
                        guard let chunk = try? JSONDecoder().decode(GenerateContentChunk.self, from: data) else { continue }

                        if let message = chunk.error?.message {
                            continuation.yield(.failed(message))
                            continue
                        }
                        // usageMetadata is cumulative-so-far and may arrive on a final chunk with
                        // empty `candidates` — parse it independent of the candidates guard below
                        // so that chunk isn't dropped, and keep only the latest (last-wins) value
                        // instead of summing per chunk (AgentSession sums `.usage` events).
                        if let json = JSONValue.parse(payload), let usage = Self.usage(from: json) {
                            latestUsage = usage
                        }
                        guard let candidate = chunk.candidates?.first else { continue }
                        for part in candidate.content?.parts ?? [] {
                            if let text = part.text, !text.isEmpty {
                                continuation.yield(.textDelta(text))
                            }
                            if let call = part.functionCall {
                                // Gemini delivers complete args in one part.
                                continuation.yield(.toolUseStart(id: call.name, name: call.name))
                                let input = JSONValue.fromFoundationObject(call.args?.value ?? [:])
                                continuation.yield(.toolUseComplete(id: call.name, name: call.name, input: input))
                            }
                        }
                        if let reason = candidate.finishReason { finishReason = reason }
                    }
                    if let usage = latestUsage {
                        continuation.yield(.usage(usage))
                    }
                    continuation.yield(.done(stopReason: finishReason))
                    continuation.finish()
                } catch StreamingHTTPError.status(_, let body) {
                    continuation.yield(.failed(Self.errorMessage(fromResponseBody: body)))
                    continuation.finish()
                } catch {
                    continuation.yield(.failed("Streaming failed: \(error.localizedDescription)"))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Usage parsing

    /// `usageMetadata.promptTokenCount`/`candidatesTokenCount` (+ `cachedContentTokenCount`).
    /// The `GenerateContentChunk` Decodable has no usage field, so this reads the raw JSON.
    nonisolated static func usage(from json: JSONValue) -> TokenUsage? {
        guard let meta = json["usageMetadata"] else { return nil }
        func int(_ k: String) -> Int { if case .number(let n)? = meta[k] { return Int(n) }; return 0 }
        return TokenUsage(input: int("promptTokenCount"), output: int("candidatesTokenCount"),
                          cacheRead: int("cachedContentTokenCount"), cacheWrite: 0)
    }

    // MARK: - Request building

    private static func makeRequest(
        baseURL: String, messages: [AgentMessage], system: String,
        tools: [AgentToolSchema], model: AgentModelConfig, apiKey: String
    ) -> URLRequest {
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let url = URL(string: "\(trimmed)/models/\(model.model):streamGenerateContent?alt=sse")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        var body: [String: Any] = [
            "system_instruction": ["parts": [["text": system]]],
            "contents": messages.map(wireContent),
        ]
        if !tools.isEmpty {
            body["tools"] = [["function_declarations": tools.map {
                ["name": $0.name, "description": $0.description, "parameters": $0.parameters.toFoundationObject()]
            }]]
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Maps one `AgentMessage` to a Gemini `content` object. Sage → "model".
    nonisolated private static func wireContent(_ message: AgentMessage) -> [String: Any] {
        let role = message.role == .assistant ? "model" : "user"
        let parts: [[String: Any]] = message.wireContent.compactMap { block in
            switch block {
            case .text(let t):
                return ["text": t]
            case .toolUse(_, let name, let input):
                return ["functionCall": ["name": name, "args": input.toFoundationObject()]]
            case .toolResult(let toolUseID, let content, _):
                // toolUseID == the function name (see class doc).
                return ["functionResponse": ["name": toolUseID, "response": ["result": content]]]
            case .image(let mediaType, let base64):
                return ["inlineData": ["mimeType": mediaType, "data": base64]]
            case .thinking:
                // `wireContent` strips `.thinking` before this switch runs, so
                // reaching here is a bug upstream. Assert it in Debug so it is
                // caught in development — but in Release, DROP the block rather
                // than killing the user's session mid-conversation. Dropping is
                // exactly what `wireContent` would have done, so nothing is lost.
                assertionFailure(".thinking reached the wire — wireContent was bypassed")
                Log.app.error("Dropped a .thinking block that reached the wire serializer")
                return nil
            }
        }
        return ["role": role, "parts": parts]
    }

    /// Test-only hook exposing `wireContent(_:)`'s `"parts"` array for a single message.
    nonisolated static func wireContentForTesting(_ message: AgentMessage) -> [[String: Any]] {
        wireContent(message)["parts"] as? [[String: Any]] ?? []
    }

    /// Test-only alias matching the shared `wirePayloadForTesting` seam name used
    /// across providers (see `ClaudeProvider`, `OpenAICompatibleProvider`).
    nonisolated static func wirePayloadForTesting(_ message: AgentMessage) -> [[String: Any]] {
        wireContentForTesting(message)
    }

    private static func errorMessage(fromResponseBody body: String) -> String {
        if let data = body.data(using: .utf8),
           let chunk = try? JSONDecoder().decode(GenerateContentChunk.self, from: data),
           let message = chunk.error?.message {
            return message
        }
        return "Gemini API request failed"
    }

    // MARK: - Wire types

    private struct GenerateContentChunk: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    struct FunctionCall: Decodable { let name: String; let args: AnyJSON? }
                    let text: String?
                    let functionCall: FunctionCall?
                }
                let parts: [Part]?
            }
            let content: Content?
            let finishReason: String?
        }
        struct ErrorPayload: Decodable { let message: String? }
        let candidates: [Candidate]?
        let error: ErrorPayload?
    }
}
