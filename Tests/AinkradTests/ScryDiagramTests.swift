import Foundation
import Testing

@testable import Ainkrad

@Suite("ScryChartParse")
struct ScryDiagramTests {
    @Test func parsesValidCSVRows() {
        let bars = ScryChartParse.bars(from: "Ada,3\nBo,7")
        #expect(
            bars == [
                ScryChartBar(label: "Ada", value: 3),
                ScryChartBar(label: "Bo", value: 7),
            ])
    }

    @Test func skipsMalformedRowsButKeepsGoodOnes() {
        // "junk" has no comma → not exactly two cells; "Cy,x" has a
        // non-numeric value. Both are dropped, "Ada,3" survives.
        let bars = ScryChartParse.bars(from: "junk\nAda,3\nCy,x")
        #expect(bars == [ScryChartBar(label: "Ada", value: 3)])
    }

    @Test func allMalformedRowsGiveEmptyResult() {
        #expect(ScryChartParse.bars(from: "junk\nmore junk").isEmpty)
    }

    @Test func emptyBodyGivesEmptyResult() {
        #expect(ScryChartParse.bars(from: "").isEmpty)
    }

    @Test func negativeValuesAreDropped() {
        let bars = ScryChartParse.bars(from: "Ada,-3\nBo,4")
        #expect(bars == [ScryChartBar(label: "Bo", value: 4)])
    }

    @Test func allNegativeValuesGiveEmptyResult() {
        #expect(ScryChartParse.bars(from: "Ada,-3\nBo,-4").isEmpty)
    }

    @Test func zeroValuesAreKept() {
        let bars = ScryChartParse.bars(from: "Ada,0\nBo,5")
        #expect(
            bars == [
                ScryChartBar(label: "Ada", value: 0),
                ScryChartBar(label: "Bo", value: 5),
            ])
    }

    @Test func emptyLabelIsDropped() {
        let bars = ScryChartParse.bars(from: ",5\nBo,4")
        #expect(bars == [ScryChartBar(label: "Bo", value: 4)])
    }
}

@Suite("ScryDiagramRouting")
struct ScryDiagramRoutingTests {
    private func element(kind: ScryElementKind, body: String) -> ScryElement {
        ScryElement(id: "el-1", kind: kind, body: body)
    }

    @Test func emptyDiagramBodyRoutesToFallback() {
        let route = ScryDiagramRouting.route(for: element(kind: .diagram, body: "   "))
        #expect(route == .diagramFallback)
    }

    @Test func nonEmptyDiagramBodyRoutesToDiagram() {
        let route = ScryDiagramRouting.route(for: element(kind: .diagram, body: "graph TD; A-->B"))
        #expect(route == .diagram(source: "graph TD; A-->B"))
    }

    @Test func chartKindRoutesToChartWhenBarsParse() {
        let route = ScryDiagramRouting.route(for: element(kind: .chart, body: "Ada,3\nBo,7"))
        #expect(
            route
                == .chart(bars: [
                    ScryChartBar(label: "Ada", value: 3),
                    ScryChartBar(label: "Bo", value: 7),
                ]))
    }

    @Test func chartKindRoutesToFallbackWhenBarsEmpty() {
        let route = ScryDiagramRouting.route(for: element(kind: .chart, body: "junk"))
        #expect(route == .chartFallback)
    }

    @Test func nonDiagramNonChartKindRoutesLikeDiagram() {
        // Default (non-.chart) branch covers every other kind, e.g. .unknown.
        let route = ScryDiagramRouting.route(for: element(kind: .unknown, body: ""))
        #expect(route == .diagramFallback)
    }
}
