import Foundation

/// Cost/capability tier used by the Model Router to order and gate candidates.
///
/// Distinct from `ModelTierCode` (see `Agents/AgentProfile.swift`), which is the
/// 5a Codable mirror used by `AgentRouting.maxTier` persistence. `ModelTier` is
/// the router's internal, `Comparable`, Int-backed representation; the two types
/// coexist and this bridges from the persisted mirror to the router type.
enum ModelTier: Int, Codable, Sendable, Comparable, CaseIterable {
    case local = 0
    case free = 1
    case cheapPaid = 2
    case premium = 3

    static func < (l: ModelTier, r: ModelTier) -> Bool { l.rawValue < r.rawValue }

    init(_ code: ModelTierCode) {
        switch code {
        case .local: self = .local
        case .free: self = .free
        case .cheapPaid: self = .cheapPaid
        case .premium: self = .premium
        }
    }
}
