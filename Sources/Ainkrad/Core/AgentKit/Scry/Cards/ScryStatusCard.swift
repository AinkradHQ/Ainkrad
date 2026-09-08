import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// `.status` — a small colored dot plus a status line.
@MainActor
struct ScryStatusCard: View {
    let element: ScryElement
    let tokens: DesignTokens

    var body: some View {
        switch element.kind {
        case .status:
            HStack(spacing: 8) {
                Circle().fill(tokens.accentPrimary).frame(width: 7, height: 7)
                Text(element.body).font(AinkradFont.display(12))
                    .foregroundStyle(tokens.foreground.opacity(0.85))
            }
        case .card:
            Text(element.body).font(AinkradFont.display(13))
                .foregroundStyle(tokens.foreground.opacity(0.85))
        default:
            Text("Unsupported element type")
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground.opacity(0.4))
        }
    }
}
