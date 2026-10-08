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

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradSkin) private var skin

    /// Colours come from `hostSkin`, which carries the user's custom accent;
    /// every scalar comes from the environment's skin.
    private var tokens: AinkradSkin { environment.themeManager.hostSkin }

    var body: some View {
        HStack(spacing: skin.spacing.sm) {
            if let shortcut {
                Text(shortcut)
                    .font(AinkradFont.mono(12, weight: .semibold))
                    .foregroundStyle(tokens.color(\.accentSecondary))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, skin.size.s6)
                    .padding(.vertical, skin.size.s2)
                    .background(
                        skin.shape(cut: skin.cut.c4).fill(tokens.color(\.accentSecondary).opacity(skin.opacity.o16))
                    )
                    .overlay(
                        skin.shape(cut: skin.cut.c4)
                            .strokeBorder(tokens.color(\.accentSecondary).opacity(skin.opacity.o45), lineWidth: 1)
                    )
            }

            Text(title)
                .font(AinkradFont.display(12, weight: .medium))
                .kerning(0.4)
                .foregroundStyle(tokens.color(\.foreground).opacity(skin.opacity.o90))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, skin.spacing.md)
        .padding(.vertical, skin.spacing.sm)
        .background(
            skin.shape(cut: skin.radius.sm).fill(tokens.color(\.surfaceElevated).opacity(skin.opacity.o92))
        )
        .overlay(
            skin.shape(cut: skin.radius.sm)
                .strokeBorder(tokens.color(\.accentPrimary).opacity(skin.opacity.o35), lineWidth: 1)
        )
        .shadow(color: skin.color(.palette("black", skin.opacity.o35)), radius: skin.size.s12, y: 4)
        // Never intercepts anything: it floats over the app's content, and a
        // transient badge that swallowed a click into the terminal underneath
        // would be a bug that only shows up under time pressure.
        .allowsHitTesting(false)
    }
}
