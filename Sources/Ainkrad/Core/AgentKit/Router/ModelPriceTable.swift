import Foundation

/// USD price per 1M tokens for a model, split by traffic kind.
struct ModelPrice: Codable, Equatable, Sendable {
    let inputPerMTok: Double
    let outputPerMTok: Double
    let cacheReadPerMTok: Double
    let cacheWritePerMTok: Double
}

/// Bundled price table (tokens -> USD) used by the Model Router's cost math.
/// Loads `Router/Resources/prices.json` from the given bundle at init; falls
/// back to a small compiled-in default set if the resource is missing so
/// tests never depend on bundle/resource wiring.
///
/// `cost(model:input:output:cacheRead:cacheWrite:)` returns `nil` when price
/// data for the model is missing — callers (usage tracker / UI) must show
/// "unknown", never a wrong or zero number for a model we simply don't price.
@MainActor
final class ModelPriceTable {
    private struct Entry: Codable {
        let id: String
        let matchPrefixes: [String]
        let price: ModelPrice
    }
    private let entries: [Entry]

    init(bundle: Bundle = .main) {
        if let url = bundle.url(forResource: "prices", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let list = try? JSONDecoder().decode([Entry].self, from: data), !list.isEmpty
        {
            entries = list
        } else {
            entries = ModelPriceTable.compiledDefaults
        }
    }

    /// Resolves a model ID to its price: exact `id` match first, then the
    /// longest matching `matchPrefixes` entry across all entries.
    func price(for modelID: String) -> ModelPrice? {
        if let exact = entries.first(where: { $0.id == modelID }) { return exact.price }
        return
            entries
            .flatMap { entry in entry.matchPrefixes.map { (entry, $0) } }
            .filter { modelID.hasPrefix($0.1) }
            .max { $0.1.count < $1.1.count }?.0.price
    }

    /// USD cost for the given token counts, or `nil` if the model has no
    /// known price (never a wrong/zero number for an unpriced model).
    func cost(model: String, input: Int, output: Int, cacheRead: Int = 0, cacheWrite: Int = 0) -> Double? {
        guard let p = price(for: model) else { return nil }
        let m = 1_000_000.0
        return Double(input) / m * p.inputPerMTok
            + Double(output) / m * p.outputPerMTok
            + Double(cacheRead) / m * p.cacheReadPerMTok
            + Double(cacheWrite) / m * p.cacheWritePerMTok
    }

    private static let zero = ModelPrice(inputPerMTok: 0, outputPerMTok: 0, cacheReadPerMTok: 0, cacheWritePerMTok: 0)
    private static let compiledDefaults: [Entry] = [
        .init(
            id: "claude-opus-4-8", matchPrefixes: ["claude-opus"],
            price: .init(inputPerMTok: 15, outputPerMTok: 75, cacheReadPerMTok: 1.5, cacheWritePerMTok: 18.75)),
        .init(
            id: "claude-sonnet-4-8", matchPrefixes: ["claude-sonnet"],
            price: .init(inputPerMTok: 3, outputPerMTok: 15, cacheReadPerMTok: 0.3, cacheWritePerMTok: 3.75)),
        .init(
            id: "claude-haiku-4-8", matchPrefixes: ["claude-haiku"],
            price: .init(inputPerMTok: 0.8, outputPerMTok: 4, cacheReadPerMTok: 0.08, cacheWritePerMTok: 1)),
        .init(
            id: "gpt-5", matchPrefixes: ["gpt-5"],
            price: .init(inputPerMTok: 10, outputPerMTok: 30, cacheReadPerMTok: 1, cacheWritePerMTok: 0)),
        .init(
            id: "gpt-5-mini", matchPrefixes: ["gpt-5-mini"],
            price: .init(inputPerMTok: 0.6, outputPerMTok: 2.4, cacheReadPerMTok: 0.06, cacheWritePerMTok: 0)),
        .init(
            id: "gemini-2.5-flash", matchPrefixes: ["gemini-2.5-flash"],
            price: .init(inputPerMTok: 0.3, outputPerMTok: 1.2, cacheReadPerMTok: 0.03, cacheWritePerMTok: 0)),
        .init(
            id: "deepseek-chat", matchPrefixes: ["deepseek"],
            price: .init(inputPerMTok: 0.27, outputPerMTok: 1.1, cacheReadPerMTok: 0.07, cacheWritePerMTok: 0)),
        .init(id: "llama3.2", matchPrefixes: ["llama"], price: zero),
        .init(id: "qwen2.5-coder", matchPrefixes: ["qwen"], price: zero),
    ]
}
