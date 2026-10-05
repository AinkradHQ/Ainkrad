import AinkradAppKit
import AinkradAppKitUI
import SwiftUI

/// Floating HUD listing running jobs. Auto-hides when idle — a permanently
/// visible empty panel is chrome that earns nothing.
///
/// Jobs belong to the engine, not to a pane, so closing the pane that started
/// a copy leaves the copy running and still visible here.
struct OperationsPanel: View {
    let engine: FileOperationEngine

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradTypography) private var typo

    var body: some View {
        if !engine.activeJobs.isEmpty {
            VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
                ForEach(engine.activeJobs) { job in
                    JobRow(job: job)
                }
            }
            .padding(AinkradSpacing.md)
            .frame(width: 280)
            .background(ChamferShape(cut: 8).fill(theme.surfaceElevated.opacity(0.95)))
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeOut(duration: 0.2), value: engine.activeJobs.count)
        }
    }
}

private struct JobRow: View {
    let job: OperationProgress

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradTypography) private var typo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(job.label)
                    .font(AinkradFontResolver.font(.caption, weight: .medium, typography: typo))
                    .foregroundStyle(theme.foreground)
                Spacer()
                Button {
                    job.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.foreground.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(job.isCancelled)
            }

            ProgressView(value: job.fraction)
                .progressViewStyle(.linear)
                .tint(theme.accentPrimary)

            // Says "items", not a byte count, because that is what is actually
            // measured — see `OperationProgress`.
            Text(
                job.isCancelled
                    ? "Cancelling…"
                    : "\(job.completedItems) of \(job.totalItems) items"
            )
            .font(AinkradFontResolver.font(.caption, typography: typo))
            .foregroundStyle(theme.foreground.opacity(0.5))

            if !job.failures.isEmpty {
                Text("\(job.failures.count) failed")
                    .font(AinkradFontResolver.font(.caption, typography: typo))
                    .foregroundStyle(theme.foreground.opacity(0.7))
            }
        }
    }
}
