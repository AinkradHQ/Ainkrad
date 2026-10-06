import AinkradAppKitUI
import AinkradHostRuntime
import SwiftUI

/// A thin status strip reflecting `DevHostModel.State`: success on a
/// load, danger with the exact rejection message on `.invalid`, nothing on
/// `.empty` (no bundle attempted yet — nothing to report). The kit's
/// `AinkradBanner`, so it carries no `Divider()`/border lines of its own.
struct ValidationBanner: View {
    let state: DevHostModel.State

    var body: some View {
        switch state {
        case .empty:
            EmptyView()
        case .loaded(let app):
            AinkradBanner(message: "loaded: \(app.id)", status: .success)
        case .invalid(let message):
            AinkradBanner(message: message, status: .danger)
        }
    }
}
