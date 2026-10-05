import Foundation

@MainActor protocol LLMProvider {
    /// Streams the assistant turn. `system` is the assembled system prompt+context;
    /// `tools` is the provider-neutral tool set the agent may call.
    func send(
        messages: [AgentMessage], system: String, tools: [AgentToolSchema],
        model: AgentModelConfig, credential: ProviderCredential
    ) -> AsyncThrowingStream<AgentEvent, Error>
}
