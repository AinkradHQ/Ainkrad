import AinkradHostRuntime
import SwiftUI

/// A thin status strip reflecting `DevHostModel.State`: green on a
/// successful load, red with the exact rejection message on `.invalid`,
/// nothing on `.empty` (no bundle attempted yet — nothing to report). Kept
/// seamless with the window body per the Cardinal HUD language: a filled
/// color strip, no `Divider()`/border lines.
struct ValidationBanner: View {
    let state: DevHostModel.State

    var body: some View {
        switch state {
        case .empty:
            EmptyView()
        case .loaded(let app):
            banner(
                message: "loaded: \(app.id)",
                systemImage: "checkmark.circle.fill",
                tint: .green
            )
        case .invalid(let message):
            banner(
                message: message,
                systemImage: "xmark.octagon.fill",
                tint: .red
            )
        }
    }

    private func banner(message: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(message)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .foregroundStyle(tint)
        .background(tint.opacity(0.15))
    }
}
