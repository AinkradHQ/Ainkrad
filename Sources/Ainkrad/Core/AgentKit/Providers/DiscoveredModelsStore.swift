import AinkradHostRuntime
import Foundation

/// Persisted map of a connection's LIVE-discovered model ids (from the provider's
/// `/models` endpoint via `ModelCatalogService`), keyed by connection id. This is
/// the shared source of truth for "what models does this connection actually
/// offer" — read by BOTH the composer's model picker AND the Auto router's
/// `candidatesProvider`, so a live-discovered model (e.g. an OpenRouter/Ollama id
/// no preset enumerates) can be selected in the pill AND auto-routed to. When a
/// connection has no live entry (never refreshed, or its fetch failed), consumers
/// fall back to the preset's `curatedModels` — the curated list is a fallback, not
/// the primary source.
struct DiscoveredModelsDocument: PersistableDocument {
    static let documentID = "discovered-models"
    /// connectionID.uuidString → discovered model ids.
    var byConnection: [String: [String]]

    init(byConnection: [String: [String]] = [:]) { self.byConnection = byConnection }

    // Host idiom: forward-compatible decoding (decodeIfPresent + default) so a
    // payload missing newer keys never throws. See SkillCommandsDocument.
    enum CodingKeys: String, CodingKey { case byConnection }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        byConnection = try c.decodeIfPresent([String: [String]].self, forKey: .byConnection) ?? [:]
    }
}

/// Observable, persisted store of per-connection live-discovered models. Written
/// by the picker's `refreshModels` on a genuinely live fetch; read by the picker
/// (dropdown options) and by `AppEnvironment.candidatesProvider` (router
/// candidates). `@Observable` so the picker UI updates when a refresh lands.
@MainActor
@Observable
final class DiscoveredModelsStore {
    private var doc: DiscoveredModelsDocument
    private let persistence: PersistenceStore

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        self.doc = persistence.load(DiscoveredModelsDocument.self) ?? DiscoveredModelsDocument()
    }

    /// Live-discovered models for a connection, or `nil` if none were ever fetched
    /// (caller falls back to `curatedModels`).
    func models(for connectionID: UUID) -> [String]? {
        doc.byConnection[connectionID.uuidString]
    }

    /// Record a connection's LIVE-discovered models. Callers must only pass a
    /// genuinely-live result (a well-formed provider response) — an EMPTY live list
    /// is authoritative and IS stored (e.g. an Ollama with nothing pulled), so the
    /// picker/router show "no models" rather than the curated fallback. A
    /// failed/parse-error fetch must NOT reach here (the caller keeps the previous
    /// entry instead). Deduped so an unchanged refresh doesn't churn persistence.
    func setModels(_ models: [String], for connectionID: UUID) {
        guard doc.byConnection[connectionID.uuidString] != models else { return }
        doc.byConnection[connectionID.uuidString] = models
        persistence.save(doc)
    }

    /// Drop entries for connections that no longer exist, so a deleted connection's
    /// stale discovered list doesn't linger in persistence. Called at bootstrap.
    func prune(keeping ids: Set<UUID>) {
        let keep = Set(ids.map(\.uuidString))
        let filtered = doc.byConnection.filter { keep.contains($0.key) }
        guard filtered.count != doc.byConnection.count else { return }
        doc.byConnection = filtered
        persistence.save(doc)
    }
}
