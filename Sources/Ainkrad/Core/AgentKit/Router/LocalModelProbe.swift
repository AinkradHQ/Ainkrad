// Sources/Ainkrad/Core/AgentKit/Router/LocalModelProbe.swift
import Foundation

/// Probes a connection for local-model availability (Ollama / LM Studio /
/// other loopback servers). Local models are zero-cost and preferred by the
/// router, but the local server may simply not be running — in that case
/// this probe resolves quickly to "unavailable" rather than hanging or
/// throwing, so the router can skip local candidates cleanly.
@MainActor
final class LocalModelProbe {
    private let catalog: ModelCatalogService
    init(catalog: ModelCatalogService) { self.catalog = catalog }

    /// Ollama has a first-class preset; LM Studio (and other local servers) ride
    /// the `custom` preset — locality is preset id OR loopback base URL.
    func isLocal(_ connection: Connection) -> Bool {
        connection.presetID == "ollama" || isLocalURL(connection.baseURL)
    }

    func isLocalURL(_ baseURL: String) -> Bool {
        baseURL.contains("localhost") || baseURL.contains("127.0.0.1")
    }

    /// Discovered local model ids, or `[]` when the local server is down —
    /// never throws, never hangs.
    func availableModels(for connection: Connection, apiKey: String) async -> [String] {
        let result = await catalog.modelsResult(
            kind: connection.kind, baseURL: connection.baseURL,
            credential: .apiKey(apiKey), curatedFallback: [])
        // Only trust a live fetch — a curated fallback for a down local server is meaningless.
        return result.isLive ? result.models : []
    }

    /// `true` when the local server is reachable.
    func probe(_ connection: Connection, apiKey: String) async -> Bool {
        await catalog.test(kind: connection.kind, baseURL: connection.baseURL, credential: .apiKey(apiKey)).ok
    }
}
