import Testing
import SwiftUI
import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal
@testable import Ainkrad

/// The severity ramp has to stay legible on the surfaces a feed row actually
/// draws on — including the HOVER surface, which is where a ramp designed
/// against the base background usually fails.
@MainActor
@Suite("Signal severity contrast")
struct SignalContrastTests {
    /// 3:1 is WCAG's threshold for large text and for non-text elements such
    /// as an icon carrying meaning, which is exactly what a severity glyph is.
    private let minimumRatio = 3.0

    /// Pairs known to fall short, with the reason — a RATCHET, not an excuse.
    /// Anything not listed here must clear the bar, so a new failure fails.
    ///
    /// All three are the FAILURE severity in a borrowed palette, and in both
    /// cases the colour is that palette's canonical red: Nord's Aurora red
    /// #BF616A and Solarized's #DC322F. Raising them to 3:1 means shipping a
    /// theme called "Nord" that is not Nord — a trade of palette fidelity
    /// against legibility that affects the whole app, not just notifications,
    /// and so is not a decision this test gets to make on its own.
    ///
    /// The consequence, stated plainly so it is not forgotten: in these two
    /// themes a FAILURE glyph is the least legible thing in the feed, which
    /// is the exact inverse of what it should be.
    private let knownShortfalls: Set<String> = [
        "nord/failure/hover",              // 2.46
        "solarizedDark/failure/hover",     // 2.12
        "solarizedDark/failure/surface",   // 2.81
    ]

    private func check(_ ratio: Double, _ key: String) {
        if knownShortfalls.contains(key) {
            // Guard the ratchet from the other side too: if a token is fixed,
            // this fails and the entry must be removed.
            #expect(ratio < minimumRatio,
                    "\(key) now passes at \(ratio) — remove it from knownShortfalls")
        } else {
            #expect(ratio >= minimumRatio, "\(key) is \(ratio)")
        }
    }

    private func severityColor(_ severity: SignalSeverity,
                               tokens: DesignTokens) -> Color {
        switch SignalPresentation.status(for: severity) {
        case .success: return tokens.success
        case .warning: return tokens.warning
        case .danger: return tokens.danger
        case .neutral: return tokens.foreground
        @unknown default: return tokens.foreground
        }
    }

    @Test("every severity reads against the panel surface, in every theme")
    func againstSurface() {
        for theme in Theme.allCases {
            let tokens = theme.tokens
            for severity in SignalSeverity.allCases {
                check(severityColor(severity, tokens: tokens)
                    .contrastRatio(against: tokens.surface),
                      "\(theme.rawValue)/\(severity.rawValue)/surface")
            }
        }
    }

    @Test("every severity still reads on the hover surface")
    func againstHoverSurface() {
        // `SignalFeedRow` fills its hover background with
        // surfaceElevated at 0.9 over the panel — the lighter surface is
        // where a ramp tuned against the darker one goes quietly illegible.
        for theme in Theme.allCases {
            let tokens = theme.tokens
            for severity in SignalSeverity.allCases {
                check(severityColor(severity, tokens: tokens)
                    .contrastRatio(against: tokens.surfaceElevated),
                      "\(theme.rawValue)/\(severity.rawValue)/hover")
            }
        }
    }

    @Test("the launcher badge's text reads on every severity tint")
    func badgeTextOnTint() {
        // The badge draws `tokens.background` on the severity colour, so this
        // is the pair that has to hold now that the tint varies.
        for theme in Theme.allCases {
            let tokens = theme.tokens
            for severity in SignalSeverity.allCases {
                check(tokens.background
                    .contrastRatio(against: severityColor(severity, tokens: tokens)),
                      "\(theme.rawValue)/\(severity.rawValue)/badge")
            }
        }
    }
}
