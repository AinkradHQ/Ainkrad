import AinkradAppKit
import SwiftUI

/// A single rail node: a small chamfered marker whose fill encodes step status.
/// Running nodes breathe via `TimelineView` (static under Reduce Motion).
struct TimelineNodeMarker: View {
    @Environment(\.ainkradSkin) private var skin
    let status: StepStatus
    /// The rail's accent tint (normal/running/done). Errors override to `errorColor`.
    let tint: Color
    let errorColor: Color
    let reduceMotion: Bool

    private var color: Color {
        switch status {
        case .running: return tint
        case .done: return tint.opacity(skin.opacity.o70)
        case .error: return errorColor
        }
    }

    var body: some View {
        Group {
            if status == .running && !reduceMotion {
                BudgetedTimelineView { date in
                    let wave = 0.5 + 0.5 * sin(date.timeIntervalSinceReferenceDate / AinkradMotion.durationBase)
                    marker.opacity(skin.opacity.o45 + skin.opacity.o55 * wave)
                }
            } else {
                marker
            }
        }
    }

    private var marker: some View {
        ChamferShape(cut: skin.cut.c2).fill(color).frame(width: skin.size.s8, height: skin.size.s8)
    }
}
