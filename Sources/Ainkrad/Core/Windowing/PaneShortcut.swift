import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// The ⌥1-9 pane shortcuts, in one place so the key handler
/// (`WorkspaceChord.paneIndex`), the tab strip's chip and the floating badge all
/// name the same thing. A shortcut the UI advertises and the handler doesn't
/// implement — or the reverse — is worse than no shortcut at all.
enum PaneShortcut {
    /// The highest pane the chord can reach. ⌥1-9 is nine, and there is no ⌥0
    /// binding, so a tenth tab genuinely has no shortcut.
    static let maximum = 9

    /// The label for a zero-based tab position, or `nil` past the ninth tab.
    static func label(forOrdinal ordinal: Int) -> String? {
        guard ordinal >= 0, ordinal < maximum else { return nil }
        return "⌥\(ordinal + 1)"
    }
}

/// A floating HUD badge naming the pane you just switched to and the shortcut
/// that gets back to it — the volume-key idiom: it appears on the switch,
/// states the fact, and leaves.
///
/// It exists because a shortcut nobody can discover is a shortcut nobody uses.
/// The tab chips advertise ⌥N while you are looking at the strip; this puts the
/// same fact in front of you at the moment you switch, which is when it means
/// something.
struct PaneShortcutBadge: View {
    let title: String
    let shortcut: String?
    let tokens: DesignTokens

    var body: some View {
        HStack(spacing: AinkradSpacing.sm) {
            if let shortcut {
                Text(shortcut)
                    .font(AinkradFont.mono(12, weight: .semibold))
                    .foregroundStyle(tokens.accentSecondary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        ChamferShape(cut: 4).fill(tokens.accentSecondary.opacity(0.16))
                    )
                    .overlay(
                        ChamferShape(cut: 4)
                            .strokeBorder(tokens.accentSecondary.opacity(0.45), lineWidth: 1)
                    )
            }

            Text(title)
                .font(AinkradFont.display(12, weight: .medium))
                .kerning(0.4)
                .foregroundStyle(tokens.foreground.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, AinkradSpacing.md)
        .padding(.vertical, AinkradSpacing.sm)
        .background(
            ChamferShape(cut: AinkradRadius.sm).fill(tokens.surfaceElevated.opacity(0.92))
        )
        .overlay(
            ChamferShape(cut: AinkradRadius.sm)
                .strokeBorder(tokens.accentPrimary.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        // Never intercepts anything: it floats over the app's content, and a
        // transient badge that swallowed a click into the terminal underneath
        // would be a bug that only shows up under time pressure.
        .allowsHitTesting(false)
    }
}
