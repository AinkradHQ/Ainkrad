import SwiftUI
import AppKit
import AinkradAppKit
import AinkradHostRuntime

/// The Sage Block's content: a transcript bound to the host's single
/// `AgentSession`, a collapsible "thinking" disclosure, and a composer. Reads
/// `AppEnvironment` directly (host-embedded built-in, like the Settings
/// sections) rather than going through `HostServices`.
struct SageRootView: View {
    // Not `private` — read from `SageRootView+Export.swift` (a `private`
    // member is file-scoped in Swift, so an extension in a different file
    // can't see it; same widening rationale `SageComposerBar` already
    // uses for its cross-file-read state).
    @Environment(AppEnvironment.self) var environment
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    var showsHeader: Bool = true
    var autoFocusComposer: Bool = false
    /// Whether the transcript should keep pinning to the newest content.
    /// Set true on every new message/turn. NOT yet cleared by user scroll —
    /// no scroll-position seam exists in this codebase (see Task 4 report);
    /// this is the minimal gate the follow-up needs to hook into.
    @State private var followTail = true
    @State private var draft = ""
    @State private var isSidebarVisible = false
    @State private var modelPicker = SageModelPickerModel()
    // Not `private` — read from `SageRootView+Export.swift`.
    @Environment(\.ainkradToastCenter) var toastCenter
    @State private var isUsageDashboardPresented = false
    @State var isExportModalPresented = false
    @State var isShareModalPresented = false
    @State private var isRunsPanelPresented = false
    @State private var isSchedulesPresented = false
    /// A generated image presented full-screen in the lightbox overlay.
    @State private var lightboxImage: NSImage?
    /// A generated video presented full-screen in the lightbox overlay.
    @State private var lightboxVideoURL: URL?
    @State var redactionsText = ""
    /// Memoizes the per-turn timeline so a streamed chunk doesn't rebuild the
    /// whole transcript — see `TranscriptTimelineCache`.
    @State private var timelineCache = TranscriptTimelineCache()

    var body: some View {
        let tokens = environment.themeManager.tokens
        let session = environment.agentSession
        let store = environment.assistantSessionStore

        HStack(spacing: 0) {
            if showsHeader && isSidebarVisible {
                SageHistorySidebar(
                    store: store,
                    tokens: tokens,
                    surfaceOpacity: environment.appAppearanceStore.surfaceOpacity("sage"),
                    onNewChat: {
                        store.syncActive(messages: session.messages)
                        store.startNewSession()
                        session.reset()
                    },
                    onSelect: { id in
                        store.syncActive(messages: session.messages)
                        session.replaceMessages(store.activate(id))
                    }
                )
                .transition(reduceMotion ? .identity : .move(edge: .leading))
            }
            chatColumn(session: session, tokens: tokens)
        }
        .onChange(of: session.messages) { _, newValue in
            environment.assistantSessionStore.syncActive(messages: newValue)
        }
        .overlay {
            if let lightboxImage {
                ImageLightboxView(image: lightboxImage, tokens: tokens) { self.lightboxImage = nil }
                    .transition(reduceMotion ? .identity : .opacity)
            } else if let lightboxVideoURL {
                VideoLightboxView(url: lightboxVideoURL, tokens: tokens) { self.lightboxVideoURL = nil }
                    .transition(reduceMotion ? .identity : .opacity)
            }
        }
        .animation(reduceMotion ? nil : AinkradMotion.present, value: lightboxImage != nil)
        .animation(reduceMotion ? nil : AinkradMotion.present, value: lightboxVideoURL != nil)
    }

    // MARK: - Chat column

    @ViewBuilder
    private func chatColumn(session: AgentSession, tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                header(tokens: tokens)
            }

            transcript(session: session, tokens: tokens)

            if case .awaitingApproval(let pending) = session.state {
                SageApprovalBar(
                    toolName: pending.call.name,
                    title: pending.preview.title,
                    tokens: tokens,
                    onDeny: { session.deny(reason: "Denied by user.") },
                    onApproveAlways: { session.approve(always: true) },
                    onApprove: { session.approve() }
                )
                .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
            } else if session.state == .idle,
                      let plan = PlanTurnHeuristics.pendingPlan(in: session.messages) {
                PlanApprovalBar(
                    plan: plan,
                    tokens: tokens,
                    onKeepPlanning: { PlanFlow.keepPlanning(plan: plan, session: session) },
                    onApproveBuild: {
                        PlanFlow.approveBuild(plan: plan, session: session, store: environment.agentStore)
                    }
                )
                .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
            }

            SkillSuggestionChip(session: session, tokens: tokens)

            SageComposerBar(
                session: session,
                tokens: tokens,
                modelPicker: modelPicker,
                draft: $draft,
                autoFocusOnAppear: autoFocusComposer,
                isUsageDashboardPresented: $isUsageDashboardPresented,
                isRunsPanelPresented: $isRunsPanelPresented,
                isSchedulesPresented: $isSchedulesPresented,
                isExportModalPresented: $isExportModalPresented,
                isShareModalPresented: $isShareModalPresented
            )
        }
        .animation(reduceMotion ? nil : AinkradMotion.present, value: session.state)
        .background {
            // Opacity-tinted surface. The blur (when enabled) is rendered by the
            // host behind the whole pane in `BlockView` — the same path every app
            // uses now — so this view only paints its opacity tint. At opacity 1.0
            // this is identical to the old opaque background.
            tokens.background.opacity(environment.appAppearanceStore.surfaceOpacity("sage"))
        }
        .ainkradModal(isPresented: $isUsageDashboardPresented) {
            UsageDashboardView(tracker: environment.usageTracker, tokens: tokens)
        }
        .ainkradModal(isPresented: $isExportModalPresented) {
            exportModalContent
        }
        .ainkradModal(isPresented: $isShareModalPresented) {
            shareModalContent
        }
        // Runs/Schedules are variable-length lists — bound them to a compact
        // centered card that scrolls internally (like Settings/Launcher),
        // never a full-height strip. `.ainkradModal` caps width (480); this
        // caps height.
        .ainkradModal(isPresented: $isRunsPanelPresented) {
            RunsPanelView(manager: environment.runManager, tokens: tokens)
                .frame(maxHeight: 520)
        }
        .ainkradModal(isPresented: $isSchedulesPresented) {
            ScheduleUIView(store: environment.scheduleStore)
                .frame(maxHeight: 520)
        }
    }

    // MARK: - Header (sidebar toggle)

    private func header(tokens: DesignTokens) -> some View {
        HStack(spacing: 12) {
            HoverSidebarToggle(tokens: tokens) {
                withAnimation(reduceMotion ? nil : AinkradMotion.present) {
                    isSidebarVisible.toggle()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    // MARK: - Transcript

    private var transcriptIsEmpty: Bool {
        environment.agentSession.messages.isEmpty
            && environment.agentSession.state == .idle
    }

    private var assistantTypography: SageTypography {
        SageTypography.resolve(
            family: environment.appAppearanceStore.fontFamily(SageApp.id),
            scale: environment.appAppearanceStore.fontScale(SageApp.id),
            globalFamily: environment.themeManager.uiFontFamily,
            globalScale: environment.themeManager.uiFontScale)
    }

    /// True during the brief `.callingTool` window before the assistant turn's
    /// `.toolUse` block is committed to `messages` — i.e. no pending card renders yet.
    /// Once the block commits, the per-message pending card takes over (Task 2).
    private func isCallingToolWithoutCard(_ session: AgentSession) -> Bool {
        guard case .callingTool = session.state else { return false }
        let hasToolUseBlock = session.messages.contains { msg in
            msg.content.contains { if case .toolUse = $0 { return true } else { return false } }
                && !msg.content.contains { if case .toolResult = $0 { return true } else { return false } }
        }
        return !hasToolUseBlock
    }

    private func emptyState() -> some View {
        AinkradEmptyState(
            icon: "sparkles",
            title: "Ask the Sage",
            message: "Type a message, or start with / for commands and @ to mention files.",
            actionTitle: nil,
            action: nil
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func transcript(session: AgentSession, tokens: DesignTokens) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                if transcriptIsEmpty {
                    emptyState()
                        .padding(.top, 60)
                } else {
                    // Lazy: a long chat materialized every row's view on every
                    // body pass, including all the markdown/diff/tool cards
                    // scrolled far out of sight.
                    LazyVStack(alignment: .leading, spacing: AinkradSpacing.lg) {
                        ForEach(timelineCache.items(for: session.messages)) { item in
                            switch item {
                            case .userBubble(let index, let message):
                                bubble(for: message, tokens: tokens)
                                    .id(index)
                                    .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 6)))
                            case .agentTurn(let id, let steps):
                                AgentTurnTimelineView(steps: steps, tokens: tokens,
                                                      typography: assistantTypography, reduceMotion: reduceMotion,
                                                      toolStream: environment.toolStreamStore,
                                                      scryStore: environment.scryStore,
                                                      onOpenImage: { lightboxImage = $0 },
                                                      onOpenVideo: { lightboxVideoURL = $0 })
                                    .id(id)
                                    .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 6)))
                            }
                        }

                        if session.state == .thinking || session.state == .streaming
                            || isCallingToolWithoutCard(session) {
                            LiveStepView(streamingText: session.streamingText,
                                         streamingBlocks: session.streamingBlocks,
                                         streamingThinking: session.streamingThinking,
                                         isStreaming: session.state == .streaming,
                                         tokens: tokens, typography: assistantTypography,
                                         reduceMotion: reduceMotion)
                                .id("streaming")
                                .transition(reduceMotion ? .identity : .opacity)
                        }

                        if case .awaitingApproval(let pending) = session.state {
                            // Render the pending tool as an in-rail node (running
                            // marker + spine), so an approval reads as the current
                            // step of the timeline. The Approve/Deny/Always buttons
                            // stay in the docked SageApprovalBar below.
                            HStack(alignment: .top, spacing: 10) {
                                TimelineRailGutter(status: .running, tokens: tokens, reduceMotion: reduceMotion)
                                ToolCallCardView(
                                    toolName: pending.call.name,
                                    title: pending.preview.title,
                                    summary: pending.preview.summary,
                                    diff: pending.preview.diff,
                                    tokens: tokens,
                                    pendingApproval: true,
                                    fileDiff: pending.preview.fileDiff,
                                    rejectedHunkIDs: Binding(get: { session.rejectedHunkIDs }, set: { session.setRejectedHunkIDs($0) })
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .id("approval")
                            .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 6)))
                        }

                        if case .failed(let message) = session.state {
                            errorBubble(message, session: session, tokens: tokens)
                                .transition(reduceMotion ? .identity : .opacity)
                        }
                    }
                    .padding(14)
                    // The message array is mutated inside `AgentSession`, outside
                    // any `withAnimation`, so the per-turn `.transition` above has
                    // no transaction to ride. Binding an animation to the count
                    // gives newly-inserted rows their materialize transition.
                    // Gated so Reduce Motion inserts rows instantly.
                    .animation(reduceMotion ? nil : AinkradMotion.present, value: session.messages.count)
                    .animation(reduceMotion ? nil : AinkradMotion.present, value: session.state)
                }
            }
            .scrollContentBackground(.hidden)
            .onChange(of: session.messages.count) { _, _ in
                followTail = true
                withAnimation(reduceMotion ? nil : AinkradMotion.present) { proxy.scrollTo("streaming", anchor: .bottom) }
            }
            .onChange(of: session.streamingBlocks.count) { _, _ in
                // Blocks, not text: this now fires when a new block appears
                // (a handful of times per reply) instead of on every token.
                guard followTail else { return }
                proxy.scrollTo("streaming", anchor: .bottom)
            }
        }
    }

    /// Renders a user prompt bubble: its text (right-aligned chamfer) and any
    /// attached image chips. Agent turns render through `AgentTurnTimelineView`,
    /// so this is only ever called for `.userBubble` items — the old assistant
    /// tool-card / hover-copy paths moved to the timeline.
    @ViewBuilder
    private func bubble(for message: AgentMessage, tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !message.text.isEmpty {
                textBubble(for: message, tokens: tokens)
            }
            ForEach(Array(message.content.enumerated()), id: \.offset) { _, block in
                if case .image(let mediaType, let base64) = block {
                    imageChip(mediaType: mediaType, base64: base64, tokens: tokens)
                }
            }
        }
    }

    /// Renders an attached image as a thumbnail, falling back to a `[image]` chip
    /// when the base64 payload can't be decoded (e.g. malformed/truncated data).
    @ViewBuilder
    private func imageChip(mediaType: String, base64: String, tokens: DesignTokens) -> some View {
        if let data = Data(base64Encoded: base64), let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 160, maxHeight: 160)
                .clipShape(ChamferShape(cut: AinkradRadius.md))
        } else {
            Text("[image]")
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground.opacity(0.6))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.3)))
        }
    }

    private func textBubble(for message: AgentMessage, tokens: DesignTokens) -> some View {
        let isUser = message.role == .user
        return HStack {
            if isUser { Spacer(minLength: 40) }

            Group {
                if isUser {
                    Text(message.text)
                        .font(AinkradFont.display(13))
                        .foregroundStyle(tokens.foreground.opacity(0.9))
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.accentPrimary.opacity(0.18)))
                        .shadow(color: tokens.accentPrimary.opacity(0.12), radius: 6)
                } else {
                    SageMarkdownText(text: message.text, tokens: tokens, typography: assistantTypography)
                }
            }

            if !isUser { Spacer(minLength: 40) }
        }
    }

    private func errorBubble(_ message: String, session: AgentSession, tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.danger)
                Text("Something went wrong")
                    .font(AinkradFont.display(12, weight: .semibold))
                    .foregroundStyle(tokens.foreground.opacity(0.85))
                Spacer()
            }
            Text(message)
                .font(AinkradFont.mono(11))
                .foregroundStyle(tokens.foreground.opacity(0.85))
                .textSelection(.enabled)   // never truncated — an unreadable error is useless
            HStack {
                Spacer()
                ErrorRetryButton(tokens: tokens) { session.retryLastTurn() }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.45)))
        .overlay(alignment: .leading) {
            Rectangle().fill(tokens.danger).frame(width: 2)
        }
        .shadow(color: tokens.danger.opacity(0.14), radius: 7)
    }

}
