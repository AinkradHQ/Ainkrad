// Sources/Ainkrad/Core/AgentKit/Providers/ProviderPreset.swift
import Foundation

/// A curated provider template. Prefills base URL, key requirement, and a
/// fallback model list; `custom` lets the user paste an arbitrary
/// OpenAI-compatible endpoint. Live model discovery (`ModelCatalogService`)
/// supersedes `curatedModels` whenever it succeeds.
struct ProviderPreset: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let kind: ProviderKind
    let defaultBaseURL: String
    let requiresKey: Bool
    let allowsBaseURLEdit: Bool
    let curatedModels: [String]
}

extension ProviderPreset {
    static let custom = ProviderPreset(
        id: "custom", displayName: "Custom", kind: .openAICompatible,
        defaultBaseURL: "", requiresKey: true, allowsBaseURLEdit: true, curatedModels: [])

    static let all: [ProviderPreset] = [
        ProviderPreset(
            id: "openai", displayName: "OpenAI", kind: .openAICompatible,
            defaultBaseURL: "https://api.openai.com/v1", requiresKey: true,
            allowsBaseURLEdit: false, curatedModels: ["gpt-5", "gpt-5-mini"]),
        ProviderPreset(
            id: "claude", displayName: "Claude", kind: .claude,
            defaultBaseURL: "https://api.anthropic.com/v1", requiresKey: true,
            allowsBaseURLEdit: false, curatedModels: ["claude-opus-4-8", "claude-sonnet-4-8", "claude-haiku-4-8"]),
        ProviderPreset(
            id: "openrouter", displayName: "OpenRouter", kind: .openAICompatible,
            defaultBaseURL: "https://openrouter.ai/api/v1", requiresKey: true,
            allowsBaseURLEdit: false, curatedModels: ["openai/gpt-5", "anthropic/claude-opus-4-8"]),
        ProviderPreset(
            id: "groq", displayName: "Groq", kind: .openAICompatible,
            defaultBaseURL: "https://api.groq.com/openai/v1", requiresKey: true,
            allowsBaseURLEdit: false, curatedModels: ["llama-3.3-70b-versatile"]),
        ProviderPreset(
            id: "deepseek", displayName: "DeepSeek", kind: .openAICompatible,
            defaultBaseURL: "https://api.deepseek.com/v1", requiresKey: true,
            allowsBaseURLEdit: false, curatedModels: ["deepseek-chat", "deepseek-reasoner"]),
        ProviderPreset(
            id: "xai", displayName: "xAI", kind: .openAICompatible,
            defaultBaseURL: "https://api.x.ai/v1", requiresKey: true,
            allowsBaseURLEdit: false, curatedModels: ["grok-4", "grok-3"]),
        ProviderPreset(
            id: "mistral", displayName: "Mistral", kind: .openAICompatible,
            defaultBaseURL: "https://api.mistral.ai/v1", requiresKey: true,
            allowsBaseURLEdit: false, curatedModels: ["mistral-large-latest"]),
        ProviderPreset(
            id: "ollama", displayName: "Ollama", kind: .openAICompatible,
            defaultBaseURL: "http://localhost:11434/v1", requiresKey: false,
            allowsBaseURLEdit: true, curatedModels: ["llama3.2", "qwen2.5-coder"]),
        ProviderPreset(
            id: "gemini", displayName: "Gemini", kind: .gemini,
            defaultBaseURL: "https://generativelanguage.googleapis.com/v1beta", requiresKey: true,
            allowsBaseURLEdit: false, curatedModels: ["gemini-2.5-pro", "gemini-2.5-flash"]),
        custom,
    ]

    static func preset(id: String) -> ProviderPreset {
        all.first { $0.id == id } ?? custom
    }
}
