import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Cardinal-HUD Scheduler: a create editor (name, NL schedule text — compiled
/// live via `NaturalLanguageCronCompiler` with a next-fire preview — trigger
/// kind, prompt, and Add) plus a list of existing `AgentSchedule`s with
/// enable/disable, last-fired/last-result, and delete. Reads/writes
/// exclusively through `ScheduleStore` — no direct persistence access here,
/// mirroring `SkillsManagerView`'s view/store split. Screenshot-gated; no
/// native SwiftUI controls (Picker/Menu/.sheet/Slider/ColorPicker/
/// SecureField/Stepper/Toggle/TextField/Button) — every control is an
/// `Ainkrad*` component.
@MainActor
struct ScheduleUIView: View {
    @Environment(AppEnvironment.self) private var environment
    let store: ScheduleStore

    private enum TriggerKind: String, CaseIterable, Hashable {
        case time = "Time (NL schedule)"
        case fileChange = "File change"
        case gitChange = "Git change"
        case webhook = "Webhook"
    }

    @State private var draftName = ""
    @State private var draftWhen = ""          // NL schedule, used when kind == .time
    @State private var draftPrompt = ""
    @State private var draftKind: TriggerKind = .time
    @State private var draftPath = ""          // used when kind == .fileChange / .gitChange
    @State private var draftGlob = ""

    var body: some View {
        let tokens = environment.themeManager.tokens

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AinkradSettingsPanel(title: "New schedule",
                                     hint: "Have the agent run on a timer, a file change, a git change, or an incoming webhook.") {
                    editor(tokens: tokens)
                }

                AinkradSettingsPanel(title: "Schedules (\(store.schedules.count))",
                                     hint: "Existing schedules, with enable/disable and last-run status.") {
                    list(tokens: tokens)
                }
            }
            .padding(18)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Editor

    private var compiledCron: CronExpression? {
        draftKind == .time ? NaturalLanguageCronCompiler.compile(draftWhen) : nil
    }

    private func editor(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AinkradTextField(text: $draftName, placeholder: "Name")

            AinkradSelect(items: TriggerKind.allCases, selection: $draftKind, label: { $0.rawValue })

            switch draftKind {
            case .time:
                AinkradTextField(text: $draftWhen, placeholder: "e.g. every weekday at 9am")
                if let cron = compiledCron {
                    Text("Compiled: \(cron.text)")
                        .font(AinkradFont.mono(9))
                        .foregroundStyle(tokens.foreground.opacity(0.55))
                } else if !draftWhen.isEmpty {
                    Text("Couldn't understand that schedule.")
                        .font(AinkradFont.mono(9))
                        .foregroundStyle(tokens.danger.opacity(0.9))
                }
            case .fileChange:
                AinkradTextField(text: $draftPath, placeholder: "Directory to watch (absolute path)")
                AinkradTextField(text: $draftGlob, placeholder: "Glob filter, e.g. *.swift (optional)")
            case .gitChange:
                AinkradTextField(text: $draftPath, placeholder: "Repository path (absolute path)")
            case .webhook:
                Text("Fires when the webhook endpoint receives an authenticated request.")
                    .font(AinkradFont.mono(9))
                    .foregroundStyle(tokens.foreground.opacity(0.55))
            }

            AinkradTextArea(text: $draftPrompt, placeholder: "What should the agent do?",
                            minHeight: 60, maxHeight: 160)

            AinkradButton(title: "Add", style: canAdd ? .primary : .ghost) { addSchedule() }
                .disabled(!canAdd)
        }
        .padding(14)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.4)))
    }

    private var canAdd: Bool {
        guard !draftName.isEmpty, !draftPrompt.isEmpty else { return false }
        switch draftKind {
        case .time: return compiledCron != nil
        case .fileChange, .gitChange: return !draftPath.isEmpty
        case .webhook: return true
        }
    }

    private func addSchedule() {
        let trigger: ScheduleTrigger
        switch draftKind {
        case .time:
            guard let cron = compiledCron else { return }
            trigger = .time(cron: cron)
        case .fileChange:
            trigger = .fileChange(path: draftPath, glob: draftGlob.isEmpty ? nil : draftGlob)
        case .gitChange:
            trigger = .gitChange(repoPath: draftPath)
        case .webhook:
            // No independent id (M7 Wave B / B3 fix): the real webhook path
            // keys off the owning `AgentSchedule.id`, never this case's payload.
            trigger = .webhook
        }
        store.upsert(AgentSchedule(
            name: draftName, trigger: trigger, prompt: draftPrompt,
            posture: SavedExecutionPosture(permissionMode: "ask", sandboxProfileID: "workspace-write")))
        draftName = ""; draftWhen = ""; draftPrompt = ""; draftPath = ""; draftGlob = ""
    }

    // MARK: - List

    @ViewBuilder
    private func list(tokens: DesignTokens) -> some View {
        if store.schedules.isEmpty {
            AinkradEmptyState(
                icon: "clock.badge",
                title: "No schedules yet",
                message: "Add one above to have the agent run on a timer, a file change, a git change, or an incoming webhook."
            )
        } else {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(store.schedules) { schedule in
                    scheduleRow(schedule, tokens: tokens)
                }
            }
        }
    }

    private func scheduleRow(_ schedule: AgentSchedule, tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            AinkradListRow(
                leading: {
                    Image(systemName: schedule.enabled ? "clock.fill" : "clock")
                        .font(.system(size: 13))
                        .foregroundStyle((schedule.enabled ? tokens.accentSecondary : tokens.foreground.opacity(0.4)).opacity(0.85))
                        .frame(width: 18)
                },
                title: schedule.name,
                subtitle: schedule.prompt,
                trailing: {
                    HStack(spacing: 6) {
                        AinkradButton(title: schedule.enabled ? "Disable" : "Enable", style: .secondary) {
                            store.setEnabled(schedule.id, !schedule.enabled)
                        }
                        AinkradButton(title: "Delete", style: .danger) { store.delete(schedule.id) }
                    }
                }
            )

            if schedule.lastFired != nil || schedule.lastRunID != nil {
                lastRunRow(schedule, tokens: tokens)
            }
        }
    }

    /// Per-schedule last-run link into the Runs panel: shows the last-fired
    /// timestamp and, when a run was recorded, a link that jumps straight to
    /// it in `environment.runManager`'s history rather than making the user
    /// hunt for it.
    private func lastRunRow(_ schedule: AgentSchedule, tokens: DesignTokens) -> some View {
        let lastRun = schedule.lastRunID.flatMap { id in environment.runManager.runs.first { $0.id == id } }

        return HStack(spacing: 8) {
            if let lastFired = schedule.lastFired {
                Text("Last fired \(lastFired.formatted())")
                    .font(AinkradFont.mono(9))
                    .foregroundStyle(tokens.foreground.opacity(0.45))
            }
            if let lastRun {
                Text("· \(lastRun.status.rawValue)")
                    .font(AinkradFont.mono(9))
                    .foregroundStyle(statusColor(lastRun.status, tokens: tokens).opacity(0.85))
            }
        }
        .padding(.horizontal, AinkradSpacing.md)
    }

    private func statusColor(_ status: AgentRunStatus, tokens: DesignTokens) -> Color {
        switch status {
        case .done: return tokens.accentSecondary
        case .failed, .interrupted: return tokens.danger
        default: return tokens.foreground
        }
    }
}
