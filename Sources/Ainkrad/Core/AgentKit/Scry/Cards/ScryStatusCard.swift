import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// `.status` — a small colored dot plus a status line.
@MainActor
struct ScryStatusCard: View {
    let element: ScryElement
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        switch element.kind {
        case .status:
            HStack(spacing: 8) {
                Circle().fill(theme.accentPrimary).frame(width: 7, height: 7)
                Text(element.body).font(AinkradFont.display(12))
                    .foregroundStyle(theme.foreground.opacity(0.85))
            }
        case .card:
            Text(element.body).font(AinkradFont.display(13))
                .foregroundStyle(theme.foreground.opacity(0.85))
        default:
            Text("Unsupported element type")
                .font(AinkradFont.display(12))
                .foregroundStyle(theme.foreground.opacity(0.4))
        }
    }
}
