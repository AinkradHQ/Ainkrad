import Foundation

/// Bundled catalog of known models (tiers, capabilities, context windows) used
/// by the Model Router. Loads `Router/Resources/models.json` from the given
/// bundle at init; falls back to a small compiled-in default set if the
/// resource is missing so tests never depend on bundle/resource wiring.
///
/// Distinct from `ModelCatalogService` (see `Providers/ModelCatalogService.swift`),
/// which does live HTTP model discovery against a provider's API.
@MainActor
final class ModelCatalog {
    private(set) var all: [ModelDescriptor]

    init(bundle: Bundle = .main) {
        if let url = bundle.url(forResource: "models", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let list = try? JSONDecoder().decode([ModelDescriptor].self, from: data),
            !list.isEmpty
        {
            all = list
        } else {
            all = ModelCatalog.compiledDefaults
        }
    }

    /// Resolves a model ID to its descriptor: exact `id` match first, then the
    /// longest matching `matchPrefixes` entry across all descriptors.
    func descriptor(for modelID: String) -> ModelDescriptor? {
        if let exact = all.first(where: { $0.id == modelID }) { return exact }
        return
            all
            .flatMap { descriptor in descriptor.matchPrefixes.map { (descriptor, $0) } }
            .filter { modelID.hasPrefix($0.1) }
            .max { $0.1.count < $1.1.count }?.0
    }

    static let compiledDefaults: [ModelDescriptor] = [
        .init(
            id: "claude-opus-4-8", tier: .premium, contextWindow: 200_000,
            capabilities: [.vision, .toolUse, .reasoningEffort], matchPrefixes: ["claude-opus"]),
        .init(
            id: "claude-sonnet-4-8", tier: .cheapPaid, contextWindow: 200_000,
            capabilities: [.vision, .toolUse, .reasoningEffort], matchPrefixes: ["claude-sonnet"]),
        .init(
            id: "claude-haiku-4-8", tier: .cheapPaid, contextWindow: 200_000,
            capabilities: [.vision, .toolUse], matchPrefixes: ["claude-haiku"]),
        .init(
            id: "gpt-5", tier: .premium, contextWindow: 400_000,
            capabilities: [.vision, .toolUse, .reasoningEffort], matchPrefixes: ["gpt-5"]),
        .init(
            id: "gpt-5-mini", tier: .cheapPaid, contextWindow: 400_000,
            capabilities: [.vision, .toolUse], matchPrefixes: ["gpt-5-mini"]),
        .init(
            id: "gemini-2.5-flash", tier: .cheapPaid, contextWindow: 1_000_000,
            capabilities: [.vision, .toolUse], matchPrefixes: ["gemini-2.5-flash"]),
        .init(
            id: "deepseek-chat", tier: .free, contextWindow: 64_000,
            capabilities: [.toolUse], matchPrefixes: ["deepseek"]),
        .init(
            id: "llama3.2", tier: .local, contextWindow: 128_000,
            capabilities: [.toolUse], matchPrefixes: ["llama"]),
        .init(
            id: "qwen2.5-coder", tier: .local, contextWindow: 32_000,
            capabilities: [.toolUse], matchPrefixes: ["qwen"]),
    ]
}
