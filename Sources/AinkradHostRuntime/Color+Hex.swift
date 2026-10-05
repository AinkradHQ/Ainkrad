import AppKit
// design-lint: allow-file hex-color,raw-color hex parser
import SwiftUI

extension Color {
    /// Creates a `Color` from a 6-digit RRGGBB hex string (no `#` prefix).
    public init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        self = Color(red: r, green: g, blue: b)
    }

    /// A high-contrast text color for content drawn directly on top of this
    /// color: near-white on dark fills, near-black on light fills. The choice
    /// tracks the fill's perceived (Rec. 709) luminance, so custom / theme
    /// accent colors keep their active-button labels legible — a dark accent
    /// gets light text, a light accent gets dark text. Falls back to light
    /// text if the color can't be resolved to sRGB components.
    ///
    /// Named `hostContrastingText` (not `contrastingText`) because
    /// `AinkradAppKit` already publishes its own same-named `Color.contrastingText`
    /// extension with a different formula (deviceRGB / Rec. 601 / 0.6 threshold).
    /// Before this type moved out of the `Ainkrad` app target, Swift's
    /// same-module-declaration priority silently preferred this one at every
    /// app call site over the SDK's; moving it into a second, non-local module
    /// removes that priority and the two extensions become ambiguous. Renaming
    /// preserves the exact original app behavior at every call site without
    /// relying on shadowing.
    public var hostContrastingText: Color {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return Color(white: 0.97) }
        let luminance = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
        // 0.55 rather than 0.5: warm/bright accents (orange, yellow, light
        // cyan) read better with dark text, so bias slightly toward it.
        return luminance > 0.55 ? Color(white: 0.08) : Color(white: 0.97)
    }

    /// The color as an uppercase 6-digit RRGGBB hex string (no `#`), or nil if
    /// it can't be resolved to sRGB components.
    public var hexString: String? {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(
            format: "%02X%02X%02X",
            Int((c.redComponent * 255).rounded()),
            Int((c.greenComponent * 255).rounded()),
            Int((c.blueComponent * 255).rounded())
        )
    }
}
