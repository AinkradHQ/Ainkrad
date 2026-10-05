import Foundation

/// Global cost <-> quality posture that biases which tier the Model Router's
/// candidate ordering starts escalating from.
enum RouterPolicy: String, Codable, Sendable, CaseIterable {
    case saveMoney, balanced, bestQuality
}

/// One routable candidate: a specific connection/model pairing plus its
/// static catalog metadata.
struct RouterCandidate: Equatable, Sendable {
    let connectionID: UUID
    let model: String
    let descriptor: ModelDescriptor
}

/// Pure candidate ordering + capability filtering rules for the Model Router.
/// Deterministic and side-effect free; the `ModelRouter` facade (Task 13) is
/// the only caller that wires this to live state.
enum RouterOrdering {
    /// Drops candidates lacking a capability the signal requires, or whose
    /// context window is too small for the estimated input. Hard filter —
    /// never a soft preference.
    static func capable(_ candidates: [RouterCandidate], for signal: TaskSignal) -> [RouterCandidate] {
        candidates.filter { c in
            if signal.needsVision && !c.descriptor.capabilities.contains(.vision) { return false }
            if signal.needsTools && !c.descriptor.capabilities.contains(.toolUse) { return false }
            if c.descriptor.contextWindow < signal.estimatedInputTokens { return false }
            return true
        }
    }

    /// Drops LOCAL candidates (per `isLocalConnection`) whose connection isn't
    /// in `reachableLocalConnectionIDs` — the fix for the router picking a
    /// down Ollama/LM Studio server and hanging every turn. Non-local
    /// candidates are ALWAYS kept; only a candidate that is both local AND
    /// unreachable is dropped. Pure/testable: no I/O, `reachableLocalConnectionIDs`
    /// is a pre-computed snapshot (see `LocalModelAvailability`).
    static func filterReachableCandidates(
        _ candidates: [RouterCandidate],
        reachableLocalConnectionIDs: Set<UUID>,
        isLocalConnection: (UUID) -> Bool
    ) -> [RouterCandidate] {
        candidates.filter { c in
            !isLocalConnection(c.connectionID) || reachableLocalConnectionIDs.contains(c.connectionID)
        }
    }

    /// Applies an Agent's routing bounds: `allowedModels` (if non-empty)
    /// restricts the candidate set, and `maxTier` is a hard ceiling.
    static func bounded(_ candidates: [RouterCandidate], by routing: AgentRouting) -> [RouterCandidate] {
        candidates.filter { c in
            if !routing.allowedModels.isEmpty && !routing.allowedModels.contains(c.model) { return false }
            if let ceiling = routing.maxTier, c.descriptor.tier > ModelTier(ceiling) { return false }
            return true
        }
    }

    /// Orders candidates cheapest-capable-first (local -> free -> cheapPaid ->
    /// premium) for `.saveMoney`, reversed (premium-first) for `.bestQuality`,
    /// and starting from `cheapPaid` for `.balanced`. Within a tier, `preferred`
    /// ids float to the front, in the order they're listed; unlisted ids keep
    /// their relative (stable) input order as the tie-break — the brief does
    /// not specify one, so this is the deterministic choice made here.
    static func ordered(_ candidates: [RouterCandidate], policy: RouterPolicy, preferred: [String]) -> [RouterCandidate]
    {
        let ascending = candidates.enumerated().sorted { a, b in
            if a.element.descriptor.tier != b.element.descriptor.tier {
                return a.element.descriptor.tier < b.element.descriptor.tier
            }
            let pa = preferred.firstIndex(of: a.element.model) ?? Int.max
            let pb = preferred.firstIndex(of: b.element.model) ?? Int.max
            if pa != pb { return pa < pb }
            return a.offset < b.offset
        }.map(\.element)

        switch policy {
        case .saveMoney:
            return ascending
        case .bestQuality:
            return ascending.reversed()
        case .balanced:
            let fromCheapPaid = ascending.filter { $0.descriptor.tier >= .cheapPaid }
            let belowCheapPaid = ascending.filter { $0.descriptor.tier < .cheapPaid }
            return fromCheapPaid + belowCheapPaid
        }
    }
}
