import AinkradHostRuntime
// Sources/Ainkrad/Core/AgentKit/Router/LocalModelAvailability.swift
import Foundation
import Observation

/// In-memory, non-persisted cache of which LOCAL connections (Ollama / LM
/// Studio / other loopback servers) are currently reachable — refreshed
/// asynchronously so the synchronous `candidatesProvider` (wired in
/// `AppEnvironment.bootstrap`) can gate local `RouterCandidate`s without ever
/// blocking a turn on network I/O. A stale/empty cache is always safe: it
/// just means local candidates are (temporarily) treated as unreachable and
/// the router picks a remote one instead — never a hang, never a crash.
///
/// Deliberately NOT a `PersistableDocument`: reachability is a live fact about
/// the current process's environment, not state worth restoring across
/// launches (a server that was up yesterday tells you nothing about now).
@MainActor
@Observable
final class LocalModelAvailability {
    private(set) var reachableConnectionIDs: Set<UUID> = []

    /// Probes every LOCAL connection (per `probe.isLocal`) and replaces the
    /// reachable set with exactly the ones that answered. Non-local
    /// connections are irrelevant here — they're never gated by this cache.
    func refresh(connections: [Connection], probe: LocalModelProbe, tokenFor: (Connection) -> String?) async {
        var reachable: Set<UUID> = []
        for connection in connections where probe.isLocal(connection) {
            let ok = await probe.probe(connection, apiKey: tokenFor(connection) ?? "")
            if ok { reachable.insert(connection.id) }
        }
        reachableConnectionIDs = reachable
    }
}
