import AinkradAppKit
import AinkradHostRuntime
import SwiftUI

/// Pure mapping from `PushToTalkController.Status` to the indicator's visual
/// state — kept separate from `RecordingIndicatorView` so it's unit-testable
/// without SwiftUI (M7 Slice 8 Task 14).
enum RecordingIndicatorState: Equatable {
    case hidden, recording, transcribing
    case error(String)

    static func from(_ status: PushToTalkController.Status) -> RecordingIndicatorState {
        switch status {
        case .idle: return .hidden
        case .recording: return .recording
        case .transcribing: return .transcribing
        case .failed(let message): return .error(message)
        }
    }
}

/// Cardinal-HUD recording indicator bound to `pushToTalk.status`: hidden at
/// idle, a pulsing waveform meter while recording, a themed spinner while
/// transcribing, and a compact danger glyph+message on failure. Built only
/// from kit components (`AinkradSpinner`) plus a custom `Scry`/`TimelineView`
/// waveform — no native controls, no plain `Label`/`ProgressView`.
@MainActor
struct RecordingIndicatorView: View {
    let status: PushToTalkController.Status
    let tokens: DesignTokens
    /// `VoiceService.lastNotice` — the on-device→provider fallback disclosure.
    /// Display-only; shown alongside whichever status row is active so the
    /// user learns why transcription switched backends. `nil` renders nothing.
    var notice: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            statusRow
            if let notice {
                Text(notice)
                    .font(AinkradFont.display(10))
                    .foregroundStyle(tokens.foreground.opacity(0.4))
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch RecordingIndicatorState.from(status) {
        case .hidden:
            EmptyView()
        case .recording:
            HStack(spacing: 6) {
                WaveformMeter(tint: tokens.accentSecondary)
                Text("Listening…")
                    .font(AinkradFont.display(11, weight: .medium))
                    .foregroundStyle(tokens.accentSecondary)
            }
        case .transcribing:
            HStack(spacing: 6) {
                AinkradSpinner(size: 14, tint: tokens.foreground.opacity(0.7))
                Text("Transcribing…")
                    .font(AinkradFont.display(11))
                    .foregroundStyle(tokens.foreground.opacity(0.6))
            }
        case .error(let message):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(tokens.danger)
                Text(message)
                    .font(AinkradFont.display(11))
                    .foregroundStyle(tokens.danger)
                    .lineLimit(1)
            }
        }
    }
}

/// Animated 4-bar level meter, frame-clock driven via `TimelineView` (same
/// "no toggle/animation trigger needed" pattern `AinkradSpinner` documents)
/// so it degrades to a static bar under Reduce Motion instead of looping.
private struct WaveformMeter: View {
    let tint: Color
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private let barCount = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
            Canvas { context, size in
                let barWidth = size.width / CGFloat(barCount * 2 - 1)
                for i in 0..<barCount {
                    let level: Double
                    if reduceMotion {
                        level = 0.6
                    } else {
                        let phase = timeline.date.timeIntervalSinceReferenceDate * 3 + Double(i) * 0.8
                        level = 0.35 + 0.65 * abs(sin(phase))
                    }
                    let barHeight = size.height * level
                    let x = CGFloat(i) * barWidth * 2
                    let rect = CGRect(x: x, y: size.height - barHeight, width: barWidth, height: barHeight)
                    context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(tint))
                }
            }
        }
        .frame(width: 22, height: 14)
    }
}
