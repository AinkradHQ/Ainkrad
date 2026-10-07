import Foundation
import Testing

@testable import Ainkrad

@Suite("Router ordering")
struct RouterOrderingTests {
    private func cand(_ id: String, _ tier: ModelTier, _ ctx: Int, _ caps: ModelCapability) -> RouterCandidate {
        RouterCandidate(
            connectionID: UUID(), model: id,
            descriptor: ModelDescriptor(id: id, tier: tier, contextWindow: ctx, capabilities: caps))
    }

    @Test func freeFirstOrdering() {
        let c = [
            cand("opus", .premium, 200_000, [.toolUse]),
            cand("local", .local, 128_000, [.toolUse]),
            cand("mini", .cheapPaid, 400_000, [.toolUse]),
            cand("free", .free, 64_000, [.toolUse]),
        ]
        let ordered = RouterOrdering.ordered(c, policy: .saveMoney, preferred: [])
        #expect(ordered.map(\.model) == ["local", "free", "mini", "opus"])
    }

    @Test func capabilityFilterDropsNonVision() {
        let c = [
            cand("text", .local, 128_000, [.toolUse]),
            cand("vision", .cheapPaid, 200_000, [.vision, .toolUse]),
        ]
        let capable = RouterOrdering.capable(
            c, for: TaskSignal(estimatedInputTokens: 100, needsVision: true, needsTools: true, reasoningHeavy: false))
        #expect(capable.map(\.model) == ["vision"])
    }

    @Test func contextWindowFilter() {
        let c = [
            cand("small", .local, 8_000, [.toolUse]),
            cand("big", .cheapPaid, 400_000, [.toolUse]),
        ]
        let capable = RouterOrdering.capable(
            c,
            for: TaskSignal(estimatedInputTokens: 100_000, needsVision: false, needsTools: true, reasoningHeavy: false))
        #expect(capable.map(\.model) == ["big"])
    }

    @Test func boundsApplyMaxTierAndAllowlist() {
        let c = [
            cand("local", .local, 128_000, [.toolUse]),
            cand("opus", .premium, 200_000, [.toolUse]),
        ]
        let bounded = RouterOrdering.bounded(c, by: AgentRouting(allowedModels: [], maxTier: .cheapPaid))
        #expect(bounded.map(\.model) == ["local"])
        let allow = RouterOrdering.bounded(c, by: AgentRouting(allowedModels: ["opus"], maxTier: nil))
        #expect(allow.map(\.model) == ["opus"])
    }
}
