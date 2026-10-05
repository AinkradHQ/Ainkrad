import Foundation
import Testing

@testable import Ainkrad

@Suite("ModelCatalog")
@MainActor
struct ModelCatalogTests {
    @Test func tierOrdering() {
        #expect(ModelTier.local < ModelTier.free)
        #expect(ModelTier.cheapPaid < ModelTier.premium)
    }

    @Test func resolvesByExactIdThenPrefix() {
        let cat = ModelCatalog()  // compiled-in defaults are enough
        #expect(cat.descriptor(for: "claude-opus-4-8")?.tier == .premium)
        // A dated/suffixed variant resolves via matchPrefixes.
        #expect(cat.descriptor(for: "claude-haiku-4-8-20260101")?.tier == .cheapPaid)
    }

    @Test func localModelIsLocalTierZeroCost() {
        let cat = ModelCatalog()
        let d = cat.descriptor(for: "llama3.2")
        #expect(d?.tier == .local)
    }

    @Test func visionCapabilityFlags() {
        let cat = ModelCatalog()
        #expect(cat.descriptor(for: "gpt-5")?.capabilities.contains(.vision) == true)
    }
}
