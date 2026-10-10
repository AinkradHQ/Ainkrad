import AinkradAppKit
import AinkradHostRuntime
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Sage composer: the kit's `AinkradComposer` with Sage's controls in its
/// slots — agent, permission mode and the connection·model pill on the left;
/// Runs, Schedules, the `•••` overflow and push-to-talk on the right. Owns the
/// attachment and `@file` mention state for the next send; the kit owns the
/// surface, the text area, Send and the `/` / `@` overlay (rows come from
/// `SageComposerBar+MentionOverlay.swift`).
struct SageComposerBar: View {
    // Not `private` — read from the `SageComposerBar+*.swift` extension
    // files (M7 finalize Wave D, D2 file split: `private` is file-scoped, so
    // state/dependencies touched by an extension in a different file need at
    // least `internal`).
    @Environment(AppEnvironment.self) var environment
    @Environment(\.ainkradToastCenter) var toastCenter
    // Not `private` — read from the `SageComposerBar+*.swift` extensions.
    @Environment(\.ainkradSkin) var skin
    let session: AgentSession
    // Not `private` — read from `SageComposerBar+Overflow.swift`.
    @Environment(\.ainkradTheme) var theme
    let modelPicker: SageModelPickerModel
    @Binding var draft: String
    var autoFocusOnAppear: Bool = false
    // Owned by `SageRootView` (whose top-level `VStack` fills the whole
    // Sage surface) so the `.ainkradModal` scrim/content isn't confined
    // to this short composer strip. Not `private` — set from
    // `SageComposerBar+Overflow.swift` (Wave 3 Task 7 collapses the
    // Usage trigger into the `•••` panel; same minimal-widening rationale as
    // the export/mention/palette state above).
    @Binding var isUsageDashboardPresented: Bool
    @Binding var isRunsPanelPresented: Bool
    /// M7 Slice 3b (Autonomy: scheduling/triggers) — presents `ScheduleUIView`,
    /// same `.ainkradModal` pattern as the Runs panel below. Owned by
    /// `SageRootView`, same rationale as `isUsageDashboardPresented`.
    @Binding var isSchedulesPresented: Bool
    /// Export/redaction modal presented flag. Owned by `SageRootView`,
    /// same rationale as `isUsageDashboardPresented`; the redaction text
    /// (`redactionsText`) and the modal content/export flow now live there too
    /// (`SageRootView+Export.swift`).
    @Binding var isExportModalPresented: Bool
    /// Share modal presented flag. Owned by `SageRootView`, same rationale
    /// as `isExportModalPresented`; the modal content/share flow live there too
    /// (`SageRootView+Share.swift`).
    @Binding var isShareModalPresented: Bool

    /// Images attached via drag-and-drop, carried into the NEXT `session.send`
    /// call and cleared on send (or on manual removal via its chip's ✕).
    /// Not `private` — read/written from `SageComposerBar+ImageDrop.swift`
    /// (M7 finalize Wave D, D2 file split; same minimal-widening rationale as
    /// the mention-overlay/export state below).
    @State var pendingImages: [ImageAttachment] = []

    /// `@file` mentions committed via the overlay, carried into the NEXT
    /// send() and cleared on send. Embed-mode entries inline their file
    /// content; reference-mode entries stay as the `@path` token only.
    @State var mentions: [ComposerMention] = []

    /// `•••` overflow panel state (M7 finalize follow-up: composer strip
    /// polish) — see `SageComposerBar+Overflow.swift`. Not `private`,
    /// same widening rationale as the state above (read from that extension).
    @State var isOverflowVisible = false

    /// The one height every control in the bottom strip is pinned to — the
    /// kit composer's, so Sage's slot buttons match its Send button. Not
    /// `private` — read from `SageComposerBar+Overflow.swift`.
    static var controlHeight: CGFloat { AinkradComposer<EmptyView, EmptyView, EmptyView>.controlHeight }

    var body: some View {
        let isBusy = SageComposerBar.isBusy(session.state)

        return AinkradComposer(
            text: $draft, placeholder: "Message Sage…", isEditable: !isBusy, canSend: canSend(isBusy: isBusy),
            autoFocus: autoFocusOnAppear, suggestions: suggestions(for:), onPick: picked,
            onDrop: handleDrop, onSend: send
        ) {
            if !pendingImages.isEmpty {
                attachmentChips
            }
            if !mentions.isEmpty {
                mentionChips
            }
        } leading: {
            // Agent and permission are icon buttons that cycle on click; model
            // is the only real select.
            AinkradIconButton(
                systemName: environment.agentStore.active.icon, size: Self.controlHeight,
                tooltip: "Agent: \(environment.agentStore.active.name) — Shift+Tab"
            ) {
                environment.agentStore.cycleActive()
            }

            AinkradIconButton(
                systemName: environment.agentPermissionStore.mode.glyph, size: Self.controlHeight,
                tooltip: "Permission: \(SageComposerBar.title(environment.agentPermissionStore.mode)) — ⌘⇧P"
            ) {
                environment.agentPermissionStore.cycle()
            }

            SageConnectionModelPicker(
                model: modelPicker,
                onManageConnections: { environment.isSettingsPresented = true }
            )
        } trailing: {
            // High-traffic triggers stay visible; Usage and Export collapse
            // into `overflowTrigger`'s `•••` panel.
            runsPanelTrigger

            schedulesTrigger

            overflowTrigger

            micTrigger

            RecordingIndicatorView(
                status: environment.voiceService.pushToTalk.status,
                notice: environment.voiceService.lastNotice)
        }
        .background(
            // Tab-cycle affordance (M7 Slice 5a Task 5): swallows a plain Tab
            // keyDown to advance the active agent, but ONLY when the draft is
            // empty — otherwise Tab still moves keyboard focus as normal.
            ComposerTabCycleMonitor(
                isDraftEmpty: { draft.isEmpty },
                onCycle: { environment.agentStore.cycleActive() }
            )
        )
        .ainkradToastHost()
        .onChange(of: environment.voiceService.reviewTranscript) { _, new in
            guard let new, !new.isEmpty else { return }
            draft = draft.isEmpty ? new : draft + " " + new
            environment.voiceService.reviewTranscript = nil
        }
        .padding(skin.size.s14)
    }

    /// Opens the `/usage` dashboard (session + cumulative tokens/cost/savings)
    /// in a scoped `.ainkradModal` — the same "gauge" glyph `/usage`'s text
    /// note already reports on, just visualized. A themed icon button, not a
    /// native control.
    /// Opens the live Runs monitor (M7 Slice 3 Task 11) — queue/active/history across
    /// every origin, pause/stop, in the same `.ainkradModal` pattern as Usage. A run
    /// started via `spawn_subagent` or a background schedule shows up here live, since
    /// this reads the SAME `RunManager` the run itself updates.
    private var runsPanelTrigger: some View {
        AinkradIconButton(systemName: "list.bullet.rectangle.portrait", size: Self.controlHeight, tooltip: "Runs") {
            isRunsPanelPresented = true
        }
    }

    /// Opens the Scheduler (M7 Slice 3b) — create/edit `AgentSchedule`s (time,
    /// file-change, git-change, webhook triggers) in the same `.ainkradModal`
    /// pattern as Runs/Usage above. Uses `AinkradIconButton` (rather than the
    /// bare-`Button` idiom the sibling triggers above use) so this new trigger
    /// is a proper Cardinal HUD component, not a native control.
    private var schedulesTrigger: some View {
        AinkradIconButton(systemName: "clock.badge", size: Self.controlHeight, tooltip: "Schedules") {
            isSchedulesPresented = true
        }
    }

    /// Push-to-talk mic toggle (M7 Slice 8 Task 14) — `AinkradIconButton`
    /// (Cardinal HUD, not a native control) calling `pushToTalk.toggle()`
    /// directly; the live status is reflected next to it by
    /// `RecordingIndicatorView`, not by this button's own glyph.
    private var micTrigger: some View {
        AinkradIconButton(systemName: "mic.fill", size: Self.controlHeight, tooltip: "Push to talk") {
            environment.voiceService.pushToTalk.toggle()
        }
    }

    private func canSend(isBusy: Bool) -> Bool {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return !isBusy && (hasText || !pendingImages.isEmpty)
    }

    private func send() {
        guard canSend(isBusy: SageComposerBar.isBusy(session.state)) else { return }
        let text = SageComposerBar.outgoingText(draft: draft, mentions: mentions)
        let images = pendingImages
        draft = ""
        pendingImages = []
        mentions = []
        session.send(text, images: images)
    }

    /// The text actually sent: `draft` augmented with a `<mentioned_files>`
    /// block for embed-mode mentions (path-only fallback for large/binary via
    /// `MentionFileReader.read`). Reads are resolved here on the main actor,
    /// then passed to the pure `augment` as a plain lookup so the resolver
    /// stays nonisolated/testable.
    static func outgoingText(draft: String, mentions: [ComposerMention]) -> String {
        let resolved: [String: String] = mentions.reduce(into: [:]) { acc, mention in
            if mention.mode == .embed, let content = MentionFileReader.read(path: mention.path) {
                acc[mention.path] = content
            }
        }
        return MentionContentResolver.augment(text: draft, mentions: mentions, read: { resolved[$0] })
    }

    /// Flips one mention's mode between embed and reference. Out-of-range
    /// index is a no-op (defensive against a chip removed mid-toggle).
    static func toggledMode(_ mentions: [ComposerMention], at index: Int) -> [ComposerMention] {
        guard mentions.indices.contains(index) else { return mentions }
        var copy = mentions
        copy[index].mode = copy[index].mode == .embed ? .reference : .embed
        return copy
    }

    static func isBusy(_ state: AgentSession.State) -> Bool {
        switch state {
        case .thinking, .streaming, .callingTool, .awaitingApproval: return true
        case .idle, .failed: return false
        }
    }

    static func title(_ mode: AgentPermissionMode) -> String {
        switch mode {
        case .ask: return "Ask"
        case .autoApprove: return "Auto"
        case .fullAuto: return "Full-auto"
        }
    }
}
