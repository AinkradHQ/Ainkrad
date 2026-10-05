// design-lint: allow-file font-size frame-literal spacing-literal radius-literal hex-color opacity-literal parity golden record tests
import Testing
import AppKit
import SwiftUI
@testable import Ainkrad
import AinkradAppKit
import AinkradHostRuntime

private let gallerySections = [
    "foundation", "scales", "panel", "card", "pickers", "formControls",
    "stateViews", "sectionHeader", "wave2", "wave3", "wave4", "wave5",
    "themeFoundation"
]
private let galleryThemeNames = ["neonBlue", "cyberPurple", "gruvbox"]

/// Parity renderer and test suite for Gallery sections across themes.
@MainActor
public enum GalleryParityRenderer {
    /// Renders a SwiftUI view offscreen into an NSBitmapImageRep at 2x scale.
    public static func render<V: View>(_ view: V, width: CGFloat) -> NSBitmapImageRep? {
        let envView = view
            .environment(\.ainkradMotionBudget, .frozen)
            .environment(\.colorScheme, .dark)
            .frame(width: width)
            .fixedSize(horizontal: true, vertical: true)
            .background(Color.black)

        let hostingView = NSHostingView(rootView: envView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        let targetSize = hostingView.fittingSize
        let height = targetSize.height > 0 ? targetSize.height : 600

        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hostingView
        window.layoutIfNeeded()

        let targetScale: CGFloat = 2.0
        let bitmapWidth = Int(width * targetScale)
        let bitmapHeight = Int(height * targetScale)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: bitmapWidth,
            pixelsHigh: bitmapHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: bitmapWidth * 4,
            bitsPerPixel: 32
        ) else {
            return nil
        }

        rep.size = NSSize(width: width, height: height)

        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = context

        hostingView.cacheDisplay(in: hostingView.bounds, to: rep)

        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}

@Suite("GalleryParityTests")
@MainActor
struct GalleryParityTests {
    @Test("renders all gallery section goldens accurately", arguments: gallerySections, galleryThemeNames)
    func testGallerySectionParity(section: String, themeName: String) throws {
        guard let theme = Theme(rawValue: themeName) else {
            Issue.record("Unknown theme name \(themeName)")
            return
        }

        let galleryView = ComponentGalleryView()
        let sectionView = galleryView.gallerySectionView(named: section, theme: theme)
            .padding(20)

        guard let rep = GalleryParityRenderer.render(sectionView, width: 1280) else {
            Issue.record("Failed to render section \(section) with theme \(themeName)")
            return
        }

        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            Issue.record("Failed to generate PNG data for section \(section) with theme \(themeName)")
            return
        }

        let fileManager = FileManager.default
        let currentFilePath = #filePath
        let testsDir = URL(fileURLWithPath: currentFilePath).deletingLastPathComponent()
        let goldensDir = testsDir.appendingPathComponent("Goldens")

        try fileManager.createDirectory(at: goldensDir, withIntermediateDirectories: true)
        let goldenURL = goldensDir.appendingPathComponent("\(section)-\(themeName).png")

        let isRecording = ProcessInfo.processInfo.environment["GALLERY_GOLDEN_RECORD"] == "1"

        if isRecording || !fileManager.fileExists(atPath: goldenURL.path) {
            try pngData.write(to: goldenURL)
        } else {
            let existingData = try Data(contentsOf: goldenURL)
            #expect(pngData == existingData, "Mismatch in section: \(section), theme: \(themeName)")
        }
    }
}
