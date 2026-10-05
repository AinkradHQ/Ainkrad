import Foundation
import Testing

@testable import Ainkrad

@Suite("ModelPriceTable")
@MainActor
struct ModelPriceTableTests {
    @Test func computesDollarCost() {
        let t = ModelPriceTable()
        // gpt-5-mini priced; 1M in + 1M out.
        let c = t.cost(model: "gpt-5-mini", input: 1_000_000, output: 1_000_000)
        #expect(c != nil)
        #expect(c! > 0)
    }

    @Test func localModelsAreZeroCost() {
        let t = ModelPriceTable()
        #expect(t.cost(model: "llama3.2", input: 500_000, output: 500_000) == 0)
    }

    @Test func unknownModelReturnsNil() {
        let t = ModelPriceTable()
        #expect(t.cost(model: "totally-unknown-model-xyz", input: 100, output: 100) == nil)
    }
}
