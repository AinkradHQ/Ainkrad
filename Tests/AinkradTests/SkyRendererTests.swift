import AinkradAppKit
import AinkradHostRuntime
import SwiftUI
import Testing

@testable import Ainkrad

/// Pixel-level regression tests for the sky's large-area gradient layers.
/// These layers must be soft by construction — a hard edge anywhere reads
/// as a visible band across the home screen (the exact bug this guards
/// against: the original light-ray rectangles drew hard-sided slabs).
/// Point sprites (stars/embers/fireflies/streaks) are excluded: their dots
/// are legitimately hard-edged and tiny.
@Suite("SkyRenderer softness")
@MainActor
struct SkyRendererTests {

    private let size = CGSize(width: 400, height: 330)
    private let time = 180.0

    /// Any step between adjacent pixels above this (0…1 luminance-ish scale)
    /// is a visible edge. Soft radial falloffs measure well under 0.005.
    private let hardEdgeThreshold = 0.01

    @Test("every gradient layer is free of hard edges", arguments: ["aurora", "rays", "mist", "bokeh"])
    func gradientLayersAreSoft(layerName: String) throws {
        let tokens = Theme.neonBlue.skin
        let step = try maxAdjacentPixelStep { context, canvasSize in
            switch layerName {
            case "aurora": SkyRenderer.aurora(in: &context, size: canvasSize, time: time, surge: 0, tokens: tokens)
            case "rays": SkyRenderer.lightRays(in: &context, size: canvasSize, time: time, tokens: tokens)
            case "mist": SkyRenderer.mist(in: &context, size: canvasSize, time: time, tokens: tokens)
            default: SkyRenderer.bokeh(in: &context, size: canvasSize, time: time, tokens: tokens)
            }
        }
        #expect(step < hardEdgeThreshold, "\(layerName) has a hard edge (max adjacent step \(step))")
    }

    /// The animated branch must compose its glow gradients and canvas as
    /// overlapping layers — a bare view tuple inside TimelineView stacks
    /// them vertically into hard full-width bands (the exact home-screen
    /// bug this guards). Rendering the WHOLE view with every effect off
    /// isolates the structure: only the base gradient and glows remain,
    /// which are smooth by construction.
    @Test("the animated sky's structure produces no horizontal banding")
    func animatedStructureHasNoBands() throws {
        let t = TestHome.make("sky-structure")
        defer { t.cleanup() }
        let environment = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)
        environment.skySettingsStore.setMotionEnabled(true)
        for effect in SkyEffect.allCases {
            environment.skySettingsStore.setEnabled(false, for: effect)
        }

        let view = AmbientSkyView()
            .environment(environment)
            .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let cgImage = renderer.cgImage else {
            throw NSError(domain: "SkyRendererTests", code: 2)
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        let width = rep.pixelsWide
        let height = rep.pixelsHigh

        var maxRowStep = 0.0
        var maxLuminance = 0.0
        var previousRow = [Double]()
        for y in 0..<height {
            var row = [Double](repeating: 0, count: width)
            for x in 0..<width {
                let color = rep.colorAt(x: x, y: y)!
                row[x] = Double(color.redComponent + color.greenComponent + color.blueComponent) / 3
                maxLuminance = max(maxLuminance, row[x])
            }
            if !previousRow.isEmpty {
                for x in 0..<width {
                    maxRowStep = max(maxRowStep, abs(row[x] - previousRow[x]))
                }
            }
            previousRow = row
        }

        #expect(maxLuminance > 0.02, "sky did not render — harness is broken")
        #expect(maxRowStep < hardEdgeThreshold, "animated sky has a horizontal band (max row step \(maxRowStep))")
    }

    /// Renders the layer over black and returns the largest brightness jump
    /// between horizontally or vertically adjacent pixels.
    private func maxAdjacentPixelStep(
        _ draw: @escaping (inout GraphicsContext, CGSize) -> Void
    ) throws -> Double {
        let view = Canvas { context, canvasSize in
            context.fill(Path(CGRect(origin: .zero, size: canvasSize)), with: .color(.black))
            var layerContext = context
            draw(&layerContext, canvasSize)
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let cgImage = renderer.cgImage else {
            throw NSError(domain: "SkyRendererTests", code: 1)
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        let width = rep.pixelsWide
        let height = rep.pixelsHigh

        var luminance = [Double](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let color = rep.colorAt(x: x, y: y)!
                luminance[y * width + x] =
                    Double(color.redComponent + color.greenComponent + color.blueComponent) / 3
            }
        }

        var maxStep = 0.0
        for y in 0..<height {
            for x in 0..<width {
                let value = luminance[y * width + x]
                if x + 1 < width {
                    maxStep = max(maxStep, abs(value - luminance[y * width + x + 1]))
                }
                if y + 1 < height {
                    maxStep = max(maxStep, abs(value - luminance[(y + 1) * width + x]))
                }
            }
        }
        return maxStep
    }
}
