import AinkradAppKit
import AinkradHostRuntime
import AppKit
import SwiftUI

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
    // Not `private` — read from the `SageRootView+*.swift` extensions.
    @Environment(\.ainkradSkin) var skin
    // Not `private` — read from the `SageRootView+*.swift` extensions.
    @Environment(\.ainkradTheme) var theme
    @Environment(\.ainkradStatusColors) private var statusColors
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
        let session = environment.agentSession
        let store = environment.assistantSessionStore

        GeometryReader { geo in
            let overlays = SageSidebarLayout.overlays(paneWidth: geo.size.width)
            let sidebarShown = showsHeader && isSidebarVisible
            HStack(spacing: 0) {
                if sidebarShown && !overlays { sidebar(store: store, session: session) }
                chatColumn(session: session, overlaysSidebar: sidebarShown && overlays)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onChange(of: session.messages) { _, newValue in
            environment.assistantSessionStore.syncActive(messages: newValue)
        }
        .overlay {
            if let lightboxImage {
                ImageLightboxView(image: lightboxImage) { self.lightboxImage = nil }
                    .transition(reduceMotion ? .identity : .opacity)
            } else if let lightboxVideoURL {
                VideoLightboxView(url: lightboxVideoURL) { self.lightboxVideoURL = nil }
                    .transition(reduceMotion ? .identity : .opacity)
            }
        }
        .animation(reduceMotion ? nil : AinkradMotion.present, value: lightboxImage != nil)
        .animation(reduceMotion ? nil : AinkradMotion.present, value: lightboxVideoURL != nil)
    }

    private func sidebar(store: SageSessionStore, session: AgentSession) -> some View {
        SageHistorySidebar(
            store: store,
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

    // MARK: - Chat column

    @ViewBuilder
    private func chatColumn(session: AgentSession, overlaysSidebar: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Narrow pane: the sidebar floats over the header + transcript only,
            // so the composer below keeps the full pane width and stays usable.
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    if showsHeader {
                        header()
                    }
                    transcript(session: session)
                }
                if overlaysSidebar {
                    sidebar(store: environment.assistantSessionStore, session: session)
                        .background(theme.background)
                }
            }

            if case .awaitingApproval(let pending) = session.state {
                SageDecisionBar(
                    content: .toolApproval(toolName: pending.call.name, title: pending.preview.title),
                    actions: [
                        .init(title: "Deny", style: .ghost) {
                            session.deny(reason: "Denied by user.")
                        },
                        .init(title: "Allow always", style: .secondary) {
                            session.approve(always: true)
                        },
                        .init(title: "Approve", style: .primary) { session.approve() },
                    ]
                )
                .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
            } else if session.state == .idle,
                let plan = PlanTurnHeuristics.pendingPlan(in: session.messages)
            {
                SageDecisionBar(
                    content: .plan(plan),
                    actions: [
                        .init(title: "Keep planning", style: .ghost) {
                            PlanFlow.keepPlanning(plan: plan, session: session)
                        },
                        .init(title: "Approve & Build", style: .primary) {
                            PlanFlow.approveBuild(plan: plan, session: session, store: environment.agentStore)
                        },
                    ]
                )
                .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
            }

            SkillSuggestionChip(session: session)

            SageComposerBar(
                session: session,
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
            theme.background.opacity(environment.appAppearanceStore.surfaceOpacity("sage"))
        }
        .ainkradModal(isPresented: $isUsageDashboardPresented) {
            UsageDashboardView(tracker: environment.usageTracker)
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
            RunsPanelView(manager: environment.runManager)
                .frame(maxHeight: skin.size.s520)
        }
        .ainkradModal(isPresented: $isSchedulesPresented) {
            ScheduleUIView(store: environment.scheduleStore)
                .frame(maxHeight: skin.size.s520)
        }
    }

    // MARK: - Header (sidebar toggle)

    private func header() -> some View {
        HStack(spacing: skin.spacing.md) {
            AinkradIconButton(systemName: "sidebar.left", size: skin.size.s24, tooltip: "Toggle history") {
                withAnimation(reduceMotion ? nil : AinkradMotion.present) {
                    isSidebarVisible.toggle()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, skin.size.s14)
        .frame(height: skin.size.s44)
    }

    // MARK: - Transcript

    private var transcriptIsEmpty: Bool {
        environment.agentSession.messages.isEmpty
            && environment.agentSession.state == .idle
    }

    private var assistantTypography: AinkradTypography {
        SageApp.typography(
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

    private func transcript(session: AgentSession) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                if transcriptIsEmpty {
                    emptyState()
                        .padding(.top, skin.size.s60)
                } else {
                    // Lazy: a long chat materialized every row's view on every
                    // body pass, including all the markdown/diff/tool cards
                    // scrolled far out of sight.
                    LazyVStack(alignment: .leading, spacing: AinkradSpacing.lg) {
                        ForEach(timelineCache.items(for: session.messages)) { item in
                            switch item {
                            case .userBubble(let index, let message):
                                bubble(for: message)
                                    .id(index)
                                    .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 6)))
                            case .agentTurn(let id, let steps):
                                AgentTurnTimelineView(
                                    steps: steps,
                                    typography: assistantTypography, reduceMotion: reduceMotion,
                                    toolStream: environment.toolStreamStore,
                                    scryStore: environment.scryStore,
                                    onOpenImage: { lightboxImage = $0 },
                                    onOpenVideo: { lightboxVideoURL = $0 }
                                )
                                .id(id)
                                .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 6)))
                            }
                        }

                        if session.state == .thinking || session.state == .streaming
                            || isCallingToolWithoutCard(session)
                        {
                            LiveStepView(
                                streamingText: session.streamingText,
                                streamingBlocks: session.streamingBlocks,
                                streamingThinking: session.streamingThinking,
                                isStreaming: session.state == .streaming,
                                typography: assistantTypography,
                                reduceMotion: reduceMotion
                            )
                            .id("streaming")
                            .transition(reduceMotion ? .identity : .opacity)
                        }

                        if case .awaitingApproval(let pending) = session.state {
                            // Render the pending tool as an in-rail node (running
                            // marker + spine), so an approval reads as the current
                            // step of the timeline. The Approve/Deny/Always buttons
                            // stay in the docked SageDecisionBar below.
                            HStack(alignment: .top, spacing: skin.size.s10) {
                                TimelineRailGutter(status: .running, reduceMotion: reduceMotion)
                                ToolCallCardView(
                                    toolName: pending.call.name,
                                    title: pending.preview.title,
                                    summary: pending.preview.summary,
                                    diff: pending.preview.diff,
                                    pendingApproval: true,
                                    fileDiff: pending.preview.fileDiff,
                                    rejectedHunkIDs: Binding(
                                        get: { session.rejectedHunkIDs }, set: { session.setRejectedHunkIDs($0) })
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .id("approval")
                            .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 6)))
                        }

                        if case .failed(let message) = session.state {
                            errorBubble(message, session: session)
                                .transition(reduceMotion ? .identity : .opacity)
                        }
                    }
                    .padding(skin.size.s14)
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
                withAnimation(reduceMotion ? nil : AinkradMotion.present) {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
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
    private func bubble(for message: AgentMessage) -> some View {
        VStack(alignment: .leading, spacing: skin.spacing.sm) {
            if !message.text.isEmpty {
                textBubble(for: message)
            }
            ForEach(Array(message.content.enumerated()), id: \.offset) { _, block in
                if case .image(let mediaType, let base64) = block {
                    imageChip(mediaType: mediaType, base64: base64)
                }
            }
        }
    }

    /// Renders an attached image as a thumbnail, falling back to a `[image]` chip
    /// when the base64 payload can't be decoded (e.g. malformed/truncated data).
    @ViewBuilder
    private func imageChip(mediaType: String, base64: String) -> some View {
        if let data = Data(base64Encoded: base64), let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: skin.size.s160, maxHeight: skin.size.s160)
                .clipShape(ChamferShape(cut: AinkradRadius.md))
        } else {
            Text("[image]")
                .font(AinkradFont.display(12))
                .foregroundStyle(theme.foreground.opacity(skin.opacity.o60))
                .padding(.horizontal, skin.size.s10).padding(.vertical, skin.size.s6)
                .background(ChamferShape(cut: AinkradRadius.md).fill(theme.surfaceElevated.opacity(skin.opacity.o30)))
        }
    }

    private func textBubble(for message: AgentMessage) -> some View {
        let isUser = message.role == .user
        return HStack {
            if isUser { Spacer(minLength: 40) }

            Group {
                if isUser {
                    Text(message.text)
                        .font(AinkradFont.display(13))
                        .foregroundStyle(theme.foreground.opacity(skin.opacity.o90))
                        .padding(.horizontal, skin.spacing.md).padding(.vertical, skin.size.s9)
                        .background(ChamferShape(cut: AinkradRadius.md).fill(theme.accentPrimary.opacity(skin.opacity.o18)))
                        .shadow(color: theme.accentPrimary.opacity(skin.opacity.o12), radius: skin.size.s6)
                } else {
                    SageMarkdownText(text: message.text, typography: assistantTypography)
                }
            }

            if !isUser { Spacer(minLength: 40) }
        }
    }

    private func errorBubble(_ message: String, session: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: skin.spacing.sm) {
            HStack(spacing: skin.size.s6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(skin.font(AinkradFontToken(sizeKey: "t11", scaled: false)))
                    .foregroundStyle(statusColors.danger)
                Text("Something went wrong")
                    .font(AinkradFont.display(12, weight: .semibold))
                    .foregroundStyle(theme.foreground.opacity(skin.opacity.o85))
                Spacer()
            }
            Text(message)
                .font(AinkradFont.mono(11))
                .foregroundStyle(theme.foreground.opacity(skin.opacity.o85))
                .textSelection(.enabled)  // never truncated — an unreadable error is useless
            HStack {
                Spacer()
                AinkradButton(title: "Retry", style: .ghost, icon: "arrow.clockwise") { session.retryLastTurn() }
            }
        }
        .padding(.horizontal, skin.spacing.md).padding(.vertical, skin.size.s9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChamferShape(cut: AinkradRadius.md).fill(theme.surfaceElevated.opacity(skin.opacity.o45)))
        .overlay(alignment: .leading) {
            Rectangle().fill(statusColors.danger).frame(width: skin.size.s2)
        }
        .shadow(color: statusColors.danger.opacity(skin.opacity.o14), radius: skin.size.s7)
    }

}
