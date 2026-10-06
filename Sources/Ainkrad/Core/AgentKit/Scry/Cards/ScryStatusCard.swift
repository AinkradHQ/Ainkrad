import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// `.status` — a small colored dot plus a status line (local: the kit has no
/// status dot); `.card` — a plain body line; anything else — the kit empty
/// state.
@MainActor
struct ScryStatusCard: View {
    @Environment(\.ainkradSkin) private var skin
    let element: ScryElement
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        switch element.kind {
        case .status:
            HStack(spacing: skin.spacing.sm) {
                Circle().fill(theme.accentPrimary).frame(width: skin.size.s7, height: skin.size.s7)
                Text(element.body).font(AinkradFont.display(12))
                    .foregroundStyle(theme.foreground.opacity(skin.opacity.o85))
            }
        case .card:
            Text(element.body).font(AinkradFont.display(13))
                .foregroundStyle(theme.foreground.opacity(skin.opacity.o85))
        default:
            AinkradEmptyState(
                icon: "questionmark.square.dashed", title: "Unsupported element type",
                message: "This version of Ainkrad can't draw it.")
        }
    }
}
