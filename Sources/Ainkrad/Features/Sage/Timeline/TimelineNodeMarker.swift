import SwiftUI
import AinkradAppKit

/// A single rail node: a small chamfered marker whose fill encodes step status.
/// Running nodes breathe via `TimelineView` (static under Reduce Motion).
struct TimelineNodeMarker: View {
    let status: StepStatus
    /// The rail's accent tint (normal/running/done). Errors override to `errorColor`.
    let tint: Color
    let errorColor: Color
    let reduceMotion: Bool

    private var color: Color {
        switch status {
        case .running: return tint
        case .done: return tint.opacity(0.7)
        case .error: return errorColor
        }
    }

    var body: some View {
        Group {
            if status == .running && !reduceMotion {
                BudgetedTimelineView { date in
                    let wave = 0.5 + 0.5 * sin(date.timeIntervalSinceReferenceDate / AinkradMotion.durationBase)
                    marker.opacity(0.45 + 0.55 * wave)
                }
            } else {
                marker
            }
        }
    }

    private var marker: some View {
        ChamferShape(cut: 2).fill(color).frame(width: 8, height: 8)
    }
}
