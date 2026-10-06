import AinkradAppKit
import AinkradAppKitUI
import AinkradHostRuntime
import SwiftUI

/// What a transient message is telling you.
enum HoardToastKind: Equatable {
    case copied
    case cut
    case moved
    case deleted
    case created
    case undone
    case warning
    case failure

    var symbol: String {
        switch self {
        case .copied: return "doc.on.doc.fill"
        case .cut: return "scissors"
        case .moved: return "arrow.right.doc.on.clipboard"
        case .deleted: return "trash.fill"
        case .created: return "folder.fill.badge.plus"
        case .undone: return "arrow.uturn.backward"
        case .warning: return "exclamationmark.triangle.fill"
        case .failure: return "xmark.octagon.fill"
        }
    }

    var isProblem: Bool { self == .warning || self == .failure }
}

struct HoardToastMessage: Equatable, Identifiable {
    let id = UUID()
    var kind: HoardToastKind
    var text: String
    /// Secondary line — the undo hint, or the failure detail.
    var detail: String?
    /// Per-item reasons behind a "3 failed" summary. Carried on the message so
    /// the count is always expandable to WHICH items and WHY — a summary you
    /// cannot drill into is just a number.
    var failures: [OperationFailure] = []
}

/// Transient confirmation, in the Cardinal HUD language.
///
/// The first cut used `AinkradBanner`, a full-width bar that read as an error
/// strip for what is usually a success. This is a compact capsule: an accent
/// glyph, the message, and — the part that actually matters — the undo hint,
/// so "Copied 3 items" also tells you it is reversible.
struct HoardToast: View {
    let message: HoardToastMessage
    let onDismiss: () -> Void
    /// Show the per-item reasons. Only offered when there are any.
    var onShowDetails: (() -> Void)?

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradStatusColors) private var statusColors
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @Environment(\.ainkradSkin) private var skin

    private var tokens: DesignTokens { environment.themeManager.tokens }

    private var accent: Color {
        switch message.kind {
        case .failure: return statusColors.danger
        case .warning: return statusColors.warning
        default: return tokens.accentSecondary
        }
    }

    var body: some View {
        HStack(spacing: AinkradSpacing.md) {
            // Glyph in a tinted chamfer chip — the same treatment as
            // `AinkradIconGlyph`, so it reads as part of the kit.
            Image(systemName: message.kind.symbol)
                .font(skin.font(AinkradFontToken(sizeKey: "t11", weight: "semibold", scaled: false)))
                .foregroundStyle(accent)
                .frame(width: skin.size.s22, height: skin.size.s22)
                .background(ChamferShape(cut: skin.cut.c5).fill(accent.opacity(skin.opacity.o15)))

            VStack(alignment: .leading, spacing: skin.size.s1) {
                Text(message.text)
                    .font(AinkradFontResolver.font(.body, weight: .medium, typography: typo))
                    .foregroundStyle(tokens.foreground)
                if let detail = message.detail {
                    Text(detail)
                        .font(AinkradFontResolver.font(.caption, typography: typo))
                        .foregroundStyle(tokens.foreground.opacity(skin.opacity.o50))
                }
            }

            if !message.failures.isEmpty, let onShowDetails {
                AinkradButton(title: "Details", style: .ghost, action: onShowDetails)
                    .padding(.leading, AinkradSpacing.xs)
            }

            AinkradIconButton(systemName: "xmark", size: skin.size.s16, tooltip: "Dismiss", action: onDismiss)
                .padding(.leading, AinkradSpacing.xs)
        }
        .padding(.horizontal, AinkradSpacing.md)
        .padding(.vertical, AinkradSpacing.sm)
        .background {
            ZStack {
                ChamferShape(cut: skin.cut.c8).fill(tokens.surfaceElevated.opacity(skin.opacity.o96))
                // A leading accent rule rather than a full tinted fill: colour
                // the meaning, not the whole surface.
                HStack(spacing: 0) {
                    Rectangle().fill(accent).frame(width: skin.size.s2)
                    Spacer()
                }
                .clipShape(ChamferShape(cut: skin.cut.c8))
            }
        }
        .overlay(
            ChamferShape(cut: skin.cut.c8)
                .strokeBorder(accent.opacity(skin.opacity.o35), lineWidth: 1)
        )
        .ainkradPanelGlow()
        .fixedSize()
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(
            reduceMotion ? nil : skin.motion.springs["sp30_80"].map { skin.animation($0) },
            value: message.id)
    }
}

/// The per-item reasons behind a "3 failed" summary.
///
/// Filesystem work fails constantly and normally — permission denied, a volume
/// ejected mid-copy, a file that vanished between listing and operating. The
/// count tells you something went wrong; only this tells you what to do about
/// it, so the count is never the end of the trail.
struct HoardFailureSheet: View {
    let failures: [OperationFailure]
    let onClose: () -> Void

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradStatusColors) private var statusColors
    @Environment(\.ainkradSkin) private var skin

    private var tokens: DesignTokens { environment.themeManager.tokens }

    var body: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.lg) {
            HStack(spacing: AinkradSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(skin.font(AinkradFontToken(sizeKey: "t13", weight: "semibold", scaled: false)))
                    .foregroundStyle(statusColors.warning)
                    .frame(width: skin.size.s26, height: skin.size.s26)
                    .background(ChamferShape(cut: skin.cut.c5).fill(statusColors.warning.opacity(skin.opacity.o15)))
                Text("\(failures.count) item\(failures.count == 1 ? "" : "s") failed")
                    .font(AinkradFontResolver.font(.headline, weight: .medium, typography: typo))
                    .foregroundStyle(tokens.foreground)
                Spacer(minLength: 0)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: AinkradSpacing.sm) {
                    ForEach(Array(failures.enumerated()), id: \.offset) { _, failure in
                        VStack(alignment: .leading, spacing: skin.size.s1) {
                            Text(failure.url.lastPathComponent)
                                .font(
                                    AinkradFontResolver.font(
                                        .body, weight: .medium,
                                        typography: typo)
                                )
                                .foregroundStyle(tokens.foreground)
                            Text(failure.reason)
                                .font(AinkradFontResolver.font(.caption, typography: typo))
                                .foregroundStyle(tokens.foreground.opacity(skin.opacity.o60))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(AinkradSpacing.sm)
            }
            .frame(height: skin.size.s200)
            .background(ChamferShape(cut: skin.cut.c6).fill(tokens.foreground.opacity(skin.opacity.o05)))

            HStack {
                Spacer()
                AinkradButton(title: "Done", style: .primary, action: onClose)
            }
        }
    }
}
