import Foundation
import AinkradHostRuntime

/// `LLMProvider` conformer that streams from any OpenAI-compatible
/// `POST {baseURL}/chat/completions` endpoint (OpenAI, OpenRouter, Groq,
/// DeepSeek, xAI, Mistral, Ollama, or a custom URL).
struct OpenAICompatibleProvider: LLMProvider {
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
                    let request = Self.makeRequest(baseURL: baseURL, messages: messages, system: system, tools: tools, model: model, apiKey: apiKey)
                    let bytes = try await http.post(request)

                    var finishReason: String?
                    var calls: [Int: (id: String, name: String, args: String)] = [:]

                    for try await payload in SSEParser.events(from: bytes) {
                        guard let data = payload.data(using: .utf8) else { continue }
                        guard let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data) else { continue }

                        if let errorMessage = chunk.error?.message {
                            continuation.yield(.failed(errorMessage))
                            continue
                        }

                        // The usage chunk (when the endpoint honors `stream_options.include_usage`)
                        // arrives LAST with an empty `choices` array — parse it before the
                        // `choices.first` guard below, or it would be silently skipped.
                        if let json = JSONValue.parse(payload), let usage = Self.usage(from: json) {
                            continuation.yield(.usage(usage))
                        }

                        guard let choice = chunk.choices?.first else { continue }
                        if let content = choice.delta?.content, !content.isEmpty {
                            continuation.yield(.textDelta(content))
                        }
                        for tc in choice.delta?.toolCalls ?? [] {
                            var entry = calls[tc.index] ?? (id: "", name: "", args: "")
                            if let id = tc.id { entry.id = id }
                            if let name = tc.function?.name { entry.name = name }
                            if entry.id.isEmpty == false, entry.name.isEmpty == false, calls[tc.index] == nil {
                                continuation.yield(.toolUseStart(id: entry.id, name: entry.name))
                            }
                            if let args = tc.function?.arguments, !args.isEmpty {
                                entry.args += args
                                continuation.yield(.toolInputDelta(id: entry.id, partialJSON: args))
                            }
                            calls[tc.index] = entry
                        }
                        if let reason = choice.finishReason {
                            finishReason = reason
                        }
                    }

                    if finishReason == "tool_calls" {
                        for index in calls.keys.sorted() {
                            let entry = calls[index]!
                            let input = JSONValue.parse(entry.args) ?? .object([:])
                            continuation.yield(.toolUseComplete(id: entry.id, name: entry.name, input: input))
                        }
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

    /// The final streamed chunk's `usage` object, when the endpoint honors
    /// `stream_options.include_usage`. Returns nil when absent — that chunk simply
    /// never arrives for endpoints that don't support it, which must never be an error.
    nonisolated static func usage(from json: JSONValue) -> TokenUsage? {
        guard let u = json["usage"] else { return nil }
        func int(_ k: String) -> Int { if case .number(let n)? = u[k] { return Int(n) }; return 0 }
        var cacheRead = 0
        if case .number(let n)? = u["prompt_tokens_details"]?["cached_tokens"] { cacheRead = Int(n) }
        return TokenUsage(input: int("prompt_tokens"), output: int("completion_tokens"), cacheRead: cacheRead, cacheWrite: 0)
    }

    // MARK: - Request building

    private static func makeRequest(
        baseURL: String,
        messages: [AgentMessage],
        system: String,
        tools: [AgentToolSchema],
        model: AgentModelConfig,
        apiKey: String
    ) -> URLRequest {
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        var request = URLRequest(url: URL(string: trimmed + "/chat/completions")!)
        request.httpMethod = "POST"
        // Ollama and other keyless local endpoints send no auth header.
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        var wireMessages: [[String: Any]] = [["role": "system", "content": system]]
        wireMessages.append(contentsOf: messages.flatMap(wireMessages(for:)))

        var body: [String: Any] = [
            "model": model.model,
            "stream": true,
            "messages": wireMessages,
            // Best-effort: not every OpenAI-compatible endpoint (OpenRouter/Groq/
            // DeepSeek/Ollama/LM Studio) honors this — absent usage is never an error.
            "stream_options": ["include_usage": true],
        ]
        if !tools.isEmpty {
            body["tools"] = tools.map {
                ["type": "function",
                 "function": ["name": $0.name, "description": $0.description,
                              "parameters": $0.parameters.toFoundationObject()]]
            }
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// One `AgentMessage` can expand into multiple OpenAI wire messages: an
    /// assistant turn with tool calls, then one `role:"tool"` message per result.
    nonisolated private static func wireMessages(for message: AgentMessage) -> [[String: Any]] {
        var texts: [String] = []
        var toolCalls: [[String: Any]] = []
        var toolResults: [[String: Any]] = []
        var contentParts: [[String: Any]] = []
        var hasImage = false
        for block in message.wireContent {
            switch block {
            case .text(let t):
                texts.append(t)
                contentParts.append(["type": "text", "text": t])
            case .toolUse(let id, let name, let input):
                let args = String(decoding: (try? JSONSerialization.data(withJSONObject: input.toFoundationObject())) ?? Data("{}".utf8), as: UTF8.self)
                toolCalls.append(["id": id, "type": "function",
                                  "function": ["name": name, "arguments": args]])
            case .toolResult(let toolUseID, let content, _):
                toolResults.append(["role": "tool", "tool_call_id": toolUseID, "content": content])
            case .image(let mediaType, let base64):
                hasImage = true
                contentParts.append(["type": "image_url", "image_url": ["url": "data:\(mediaType);base64,\(base64)"]])
            case .thinking:
                // `wireContent` strips `.thinking` before this switch runs, so
                // reaching here is a bug upstream. Assert it in Debug so it is
                // caught in development — but in Release, DROP the block rather
                // than killing the user's session mid-conversation. Dropping is
                // exactly what `wireContent` would have done, so nothing is lost.
                assertionFailure(".thinking reached the wire — wireContent was bypassed")
                Log.app.error("Dropped a .thinking block that reached the wire serializer")
            }
        }
        var out: [[String: Any]] = []
        if message.role == .assistant, !toolCalls.isEmpty {
            out.append(["role": "assistant", "content": texts.joined(), "tool_calls": toolCalls])
        } else if hasImage {
            // A message carrying an image must use the array content form —
            // plain string `content` has no way to embed an image_url part.
            out.append(["role": message.role.rawValue, "content": contentParts])
        } else if !texts.isEmpty || toolResults.isEmpty {
            out.append(["role": message.role.rawValue, "content": texts.joined()])
        }
        out.append(contentsOf: toolResults)
        return out
    }

    /// Test-only hook exposing the array-content form of `wireMessages(for:)` for a
    /// single message — the `"content"` array carrying `{"type":"text"|"image_url",...}`
    /// parts. Returns an empty array for text-only messages (those still wire as a
    /// plain string, not this array form).
    nonisolated static func wireContentForTesting(_ message: AgentMessage) -> [[String: Any]] {
        wireMessages(for: message).first?["content"] as? [[String: Any]] ?? []
    }

    /// Test-only alias matching the shared `wirePayloadForTesting` seam name used
    /// across providers (see `ClaudeProvider`, `GeminiProvider`).
    nonisolated static func wirePayloadForTesting(_ message: AgentMessage) -> [[String: Any]] {
        wireContentForTesting(message)
    }

    /// Best-effort human-readable message from a non-2xx response body. Never echoes the API key
    /// (the body is the server's response, not the request — the key never appears in it).
    private static func errorMessage(fromResponseBody body: String) -> String {
        if let data = body.data(using: .utf8),
           let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data),
           let message = chunk.error?.message {
            return message
        }
        return "Provider API request failed"
    }

    // MARK: - Wire types

    private struct ChatCompletionChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                struct ToolCall: Decodable {
                    struct Function: Decodable { let name: String?; let arguments: String? }
                    let index: Int
                    let id: String?
                    let function: Function?
                }
                let content: String?
                let toolCalls: [ToolCall]?
                enum CodingKeys: String, CodingKey { case content; case toolCalls = "tool_calls" }
            }
            let delta: Delta?
            let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case delta
                case finishReason = "finish_reason"
            }
        }
        struct ErrorPayload: Decodable {
            let message: String?
        }

        let choices: [Choice]?
        let error: ErrorPayload?
    }
}
