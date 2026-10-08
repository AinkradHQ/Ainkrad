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
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        if !engine.activeJobs.isEmpty {
            VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
                ForEach(engine.activeJobs) { job in
                    JobRow(job: job)
                }
            }
            .padding(AinkradSpacing.md)
            .frame(width: skin.size.s280)
            .background(skin.shape(cut: skin.cut.c8).fill(theme.surfaceElevated.opacity(skin.opacity.o95)))
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeOut(duration: skin.motion.durations.d0_2), value: engine.activeJobs.count)
        }
    }
}

/// One job: the kit's progress ring beside its label, count and failures.
private struct JobRow: View {
    let job: OperationProgress

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: AinkradSpacing.md) {
            AinkradMeter(value: job.fraction, size: skin.size.s48)

            VStack(alignment: .leading, spacing: skin.size.s4) {
                HStack {
                    Text(job.label)
                        .font(AinkradFontResolver.font(.caption, weight: .medium, typography: typo))
                        .foregroundStyle(theme.foreground)
                    Spacer()
                    AinkradIconButton(systemName: "xmark.circle.fill", size: skin.size.s16, tooltip: "Cancel") {
                        job.cancel()
                    }
                    .disabled(job.isCancelled)
                }

                // Says "items", not a byte count, because that is what is actually
                // measured — see `OperationProgress`.
                Text(
                    job.isCancelled
                        ? "Cancelling…"
                        : "\(job.completedItems) of \(job.totalItems) items"
                )
                .font(AinkradFontResolver.font(.caption, typography: typo))
                .foregroundStyle(theme.foreground.opacity(skin.opacity.o50))

                if !job.failures.isEmpty {
                    Text("\(job.failures.count) failed")
                        .font(AinkradFontResolver.font(.caption, typography: typo))
                        .foregroundStyle(theme.foreground.opacity(skin.opacity.o70))
                }
            }
        }
    }
}
