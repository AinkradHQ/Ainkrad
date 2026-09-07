// Sources/Ainkrad/Core/AgentKit/Autonomy/RunsPanelView.swift
import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// The live Runs monitor (M7 Slice 3 Task 11): queue/active/history across
/// every origin (chat, schedule, event), per-run status + streaming last log
/// line, and pause/stop actions. A run started from chat (`AgentSession`
/// dispatching `spawn_subagent`, or a future `/run` command) and this panel
/// both read the same `RunManager`, so a background run appears here live —
/// no separate polling. Built entirely from Cardinal-HUD kit components
/// (`AinkradListRow`, `AinkradButton`, `AinkradMeter`, `AinkradIconGlyph`) —
/// no native SwiftUI controls, mirroring `UsageDashboardView`.
struct RunsPanelView: View {
    let manager: RunManager
    let tokens: DesignTokens

    var body: some View {
        let runningCount = manager.active.filter { $0.status == .running }.count
        return ScrollView {
            VStack(alignment: .leading, spacing: AinkradSpacing.lg) {
                header(runningCount: runningCount)
                sectionPanel(title: "Active", runs: manager.active, showControls: true)
                sectionPanel(title: "History", runs: manager.history, showControls: false)
            }
            .padding(AinkradSpacing.lg)
        }
    }

    // MARK: - Header

    private func header(runningCount: Int) -> some View {
        HStack(spacing: AinkradSpacing.md) {
            AinkradIconGlyph(systemName: "list.bullet.rectangle.portrait", filled: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Runs")
                    .font(AinkradFont.display(15, weight: .semibold))
                    .foregroundStyle(tokens.foreground)
                Text("\(manager.active.count) active · \(manager.history.count) history")
                    .font(AinkradFont.display(11))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
            }
            Spacer(minLength: 0)
            // Concurrency gauge: running slots filled vs. the active queue depth.
            AinkradMeter(value: Double(runningCount), total: Double(max(manager.active.count, 1)),
                        label: "Running", size: 52)
        }
    }

    // MARK: - Sections

    private func sectionPanel(title: String, runs: [AgentRun], showControls: Bool) -> some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            Text("\(title.uppercased()) (\(runs.count))")
                .font(AinkradFont.display(11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(tokens.accentSecondary.opacity(0.85))

            if runs.isEmpty {
                Text(showControls ? "No active runs." : "No completed runs yet.")
                    .font(AinkradFont.display(11))
                    .foregroundStyle(tokens.foreground.opacity(0.45))
            } else {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(runs) { run in
                        row(for: run, showControls: showControls)
                    }
                }
            }
        }
    }

    private func row(for run: AgentRun, showControls: Bool) -> some View {
        AinkradListRow(
            leading: { AinkradIconGlyph(systemName: Self.icon(for: run.status), size: 22) },
            title: run.prompt,
            subtitle: Self.subtitle(for: run),
            trailing: { controls(for: run, showControls: showControls) }
        )
    }

    @ViewBuilder
    private func controls(for run: AgentRun, showControls: Bool) -> some View {
        if showControls {
            HStack(spacing: AinkradSpacing.xs) {
                if run.status == .queued {
                    AinkradButton(title: "Pause", style: .secondary) { manager.pause(run.id) }
                }
                if run.status == .paused {
                    AinkradButton(title: "Resume", style: .secondary) { manager.resume(run.id) }
                }
                if run.status == .running || run.status == .queued || run.status == .paused {
                    AinkradButton(title: "Stop", style: .danger) { manager.stop(run.id) }
                }
            }
        } else {
            AinkradIconGlyph(systemName: Self.originIcon(for: run.origin), size: 18)
        }
    }

    // MARK: - Formatting

    private static func subtitle(for run: AgentRun) -> String {
        let head = "\(run.origin.rawValue) · \(run.status.rawValue)"
        guard let last = run.logs.last, !last.isEmpty else { return head }
        return "\(head) — \(last)"
    }

    private static func icon(for status: AgentRunStatus) -> String {
        switch status {
        case .queued: return "clock"
        case .running: return "bolt.fill"
        case .paused: return "pause.circle"
        case .done: return "checkmark.circle"
        case .failed: return "xmark.octagon"
        case .interrupted: return "stop.circle"
        }
    }

    /// Small badge glyph distinguishing a history row's origin (chat/schedule/event) —
    /// history rows have no action controls, so this fills the trailing slot instead.
    private static func originIcon(for origin: AgentRunOrigin) -> String {
        switch origin {
        case .chat: return "bubble.left"
        case .schedule: return "calendar"
        case .event: return "bolt.badge.a"
        }
    }
}
