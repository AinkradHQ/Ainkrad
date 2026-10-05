import CoreGraphics
import Testing

@testable import Ainkrad

@Suite("Pane canvas metrics")
struct PaneCanvasMetricsTests {

    private let size = CGSize(width: 1000, height: 800)

    @Test("the canvas fills the workspace minus its insets when there is no tab strip")
    func canvasWithoutStrip() {
        let rect = PaneCanvasMetrics.canvasRect(in: size, showsTabStrip: false)
        #expect(rect.minX == PaneCanvasMetrics.horizontalInset)
        #expect(rect.minY == PaneCanvasMetrics.topInset)
        #expect(rect.width == size.width - PaneCanvasMetrics.horizontalInset * 2)
        #expect(rect.height == size.height - PaneCanvasMetrics.topInset - PaneCanvasMetrics.bottomInset)
    }

    @Test("the tab strip pushes the canvas down by exactly the space it reserves")
    func stripPushesCanvasDown() {
        let without = PaneCanvasMetrics.canvasRect(in: size, showsTabStrip: false)
        let with = PaneCanvasMetrics.canvasRect(in: size, showsTabStrip: true)
        let reserved = PaneCanvasMetrics.reservedTabStripHeight(showsTabStrip: true)

        #expect(reserved > 0)
        #expect(with.minY == without.minY + reserved)
        #expect(with.height == without.height - reserved)
        #expect(with.width == without.width)
    }

    /// The strip and the canvas are laid out by two different views; if they
    /// ever overlap, tabs sit on top of a terminal.
    @Test("the strip sits directly above the canvas and never overlaps it")
    func stripDoesNotOverlapCanvas() {
        let strip = PaneCanvasMetrics.tabStripRect(in: size)
        let canvas = PaneCanvasMetrics.canvasRect(in: size, showsTabStrip: true)

        #expect(strip.maxY <= canvas.minY)
        #expect(canvas.minY - strip.maxY == PaneCanvasMetrics.tabStripSpacing)
        #expect(strip.minX == canvas.minX)
        #expect(strip.width == canvas.width)
    }

    @Test("a workspace too small for its own insets yields an empty canvas, never a negative one")
    func degenerateSizesClampToZero() {
        for tiny in [CGSize.zero, CGSize(width: 4, height: 4), CGSize(width: 1000, height: 10)] {
            let rect = PaneCanvasMetrics.canvasRect(in: tiny, showsTabStrip: true)
            #expect(rect.width >= 0)
            #expect(rect.height >= 0)
        }
    }
}
