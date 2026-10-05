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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 22, height: 22)
                .background(ChamferShape(cut: 5).fill(accent.opacity(0.15)))

            VStack(alignment: .leading, spacing: 1) {
                Text(message.text)
                    .font(AinkradFontResolver.font(.body, weight: .medium, typography: typo))
                    .foregroundStyle(tokens.foreground)
                if let detail = message.detail {
                    Text(detail)
                        .font(AinkradFontResolver.font(.caption, typography: typo))
                        .foregroundStyle(tokens.foreground.opacity(0.5))
                }
            }

            if !message.failures.isEmpty, let onShowDetails {
                Button(action: onShowDetails) {
                    Text("Details")
                        .font(AinkradFontResolver.font(.caption, weight: .medium, typography: typo))
                        .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
                .padding(.leading, AinkradSpacing.xs)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(tokens.foreground.opacity(0.4))
            }
            .buttonStyle(.plain)
            .padding(.leading, AinkradSpacing.xs)
        }
        .padding(.horizontal, AinkradSpacing.md)
        .padding(.vertical, AinkradSpacing.sm)
        .background {
            ZStack {
                ChamferShape(cut: 8).fill(tokens.surfaceElevated.opacity(0.96))
                // A leading accent rule rather than a full tinted fill: colour
                // the meaning, not the whole surface.
                HStack(spacing: 0) {
                    Rectangle().fill(accent).frame(width: 2)
                    Spacer()
                }
                .clipShape(ChamferShape(cut: 8))
            }
        }
        .overlay(
            ChamferShape(cut: 8)
                .strokeBorder(accent.opacity(0.35), lineWidth: 1)
        )
        .ainkradPanelGlow()
        .fixedSize()
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(
            reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8),
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

    private var tokens: DesignTokens { environment.themeManager.tokens }

    var body: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.lg) {
            HStack(spacing: AinkradSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(statusColors.warning)
                    .frame(width: 26, height: 26)
                    .background(ChamferShape(cut: 5).fill(statusColors.warning.opacity(0.15)))
                Text("\(failures.count) item\(failures.count == 1 ? "" : "s") failed")
                    .font(AinkradFontResolver.font(.headline, weight: .medium, typography: typo))
                    .foregroundStyle(tokens.foreground)
                Spacer(minLength: 0)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: AinkradSpacing.sm) {
                    ForEach(Array(failures.enumerated()), id: \.offset) { _, failure in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(failure.url.lastPathComponent)
                                .font(
                                    AinkradFontResolver.font(
                                        .body, weight: .medium,
                                        typography: typo)
                                )
                                .foregroundStyle(tokens.foreground)
                            Text(failure.reason)
                                .font(AinkradFontResolver.font(.caption, typography: typo))
                                .foregroundStyle(tokens.foreground.opacity(0.6))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(AinkradSpacing.sm)
            }
            .frame(height: 200)
            .background(ChamferShape(cut: 6).fill(tokens.foreground.opacity(0.05)))

            HStack {
                Spacer()
                AinkradButton(title: "Done", style: .primary, action: onClose)
            }
        }
        .padding(AinkradSpacing.xl)
        .frame(width: 520)
        .hudPanelChrome(tokens: tokens)
    }
}
