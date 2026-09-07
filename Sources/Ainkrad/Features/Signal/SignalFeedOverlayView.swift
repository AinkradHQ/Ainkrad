import SwiftUI
import AppKit
import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal

/// Hosts `SignalFeedIsland` as a dismissible overlay, matching the other HUD
/// overlays (scrim tap to dismiss, fade transition, no separator chrome).
struct SignalFeedOverlayView: View {
    let center: SignalCenter
    /// Passed in rather than read from `AppEnvironment`: a view that reaches for
    /// the whole environment cannot be rendered without one, which broke the
    /// snapshot suite the moment action routing was added — and broke it by
    /// CRASHING the test runner, so the run reported "passed" for the handful of
    /// tests that had already finished.
    var hub: SignalEmitterHub?
    let onDismiss: () -> Void

    @Environment(\.ainkradTheme) private var theme
    @State private var searchResults: [SignalEvent]?
    @State private var pendingDestructive: (SignalEvent, SignalAction)?
    @State private var viewState = SignalViewState()
    @State private var query = ""
    /// Which rows are showing their body in full. Not persisted: an expansion
    /// is a glance at one thing, not a view the user built.
    @State private var expanded: Set<UUID> = []

    /// Set by the bootstrap so the view the user built survives dismissal.
    var viewStateStore: SignalViewStateStore?
    /// Opens this source's notification settings. Passed in rather than read
    /// from the environment, so the overlay stays renderable in a snapshot —
    /// the reason recorded on `hub` above.
    var onConfigureSource: (SignalSource) -> Void = { _ in }

    private var events: [SignalEvent] { searchResults ?? center.recent }

    /// Sized to the window rather than pinned at 820x560.
    ///
    /// The row's own comment says what the feed is chiefly FOR: reading a build
    /// error. That is the payload that needs height, and a fixed box meant
    /// expanding a row scrolled rather than revealed, however much screen was
    /// going spare. Clamped at both ends — below the minimum the rail and the
    /// header stop fitting side by side, and above the maximum a line of body
    /// text gets too long to track back to the next line.
    ///
    /// Proportional rather than a drag handle: this is a HUD overlay like every
    /// other one in the app, none of which the user resizes by hand, and a grip
    /// would be the only one of its kind.
    static func width(in container: CGSize) -> CGFloat {
        min(max(container.width * 0.62, 720), 1100)
    }

    static func height(in container: CGSize) -> CGFloat {
        min(max(container.height * 0.72, 480), 900)
    }

    var body: some View {
        GeometryReader { proxy in
        ZStack {
            // The shared backdrop value, not a private 0.32: the feed sat
            // visibly lighter than the Launcher and Settings scrims for no
            // reason anyone recorded.
            Color.black.opacity(OverlayChrome.backdropOpacity)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            // The shared HUD panel finish, same as every other overlay in the
            // app: blur backing, chamfered clip, luminous accent stroke and
            // corner brackets. A plain rounded rectangle read as a web modal.
            AinkradPanel(showsBrackets: true) {
                SignalFeedIsland(
                    events: events,
                    unread: center.totalUnread,
                    repeatCounts: center.repeatCounts,
                    readIDs: center.readIDs,
                    isDegraded: center.isDegraded,
                    viewState: $viewState,
                    searchText: $query,
                    searchResultCount: searchResults?.count,
                    onActivate: { event in center.activate(event) },
                    onAction: { event, action in
                        guard let hub else { return }
                        if let needsConfirmation = SignalActionRouter(hub: hub).invoke(event, action) {
                            pendingDestructive = (event, needsConfirmation)
                        }
                    },
                    onMarkAllRead: {
                        // Scoped to what is on screen. "Mark all read" while a
                        // filter is up used to clear rows the user could not
                        // see, which is unrecoverable without markUnread.
                        center.markAllRead(filter: viewState.filter)
                    },
                    onConfigureSource: onConfigureSource,
                    menuItems: { menuItems(for: $0) },
                    pinnedIDs: center.pinnedIDs,
                    expandedIDs: $expanded,
                    isMuted: center.rules.suppression.isSuppressing(at: Date()),
                    onSnooze: { $0.apply(to: &center.rules.suppression, at: Date()) },
                    onResume: { SignalSnooze.lift(&center.rules.suppression) })
                    .frame(width: Self.width(in: proxy.size),
                           height: Self.height(in: proxy.size))
            }
        }
        .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onAppear { if let stored = viewStateStore?.load() { viewState = stored } }
        .onChange(of: viewState) { _, new in viewStateStore?.save(new) }
        .onChange(of: query) { _, new in
            // Live rather than submit-only: a search you have to press Return
            // for reads as broken when the list does not move.
            let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
            searchResults = trimmed.isEmpty ? nil : center.search(trimmed)
        }
        .confirmationDialog(
            pendingDestructive.map { "\($0.1.label)?" } ?? "",
            isPresented: Binding(get: { pendingDestructive != nil },
                                 set: { if !$0 { pendingDestructive = nil } }),
            titleVisibility: .visible
        ) {
            if let (event, action) = pendingDestructive {
                Button(action.label, role: .destructive) {
                    if let hub { SignalActionRouter(hub: hub).dispatch(event, action) }
                    pendingDestructive = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingDestructive = nil }
        } message: {
            Text("This action was published by the app and cannot be undone from here.")
        }
    }

    /// The row's right-click menu, built against live rules so the item reads
    /// "Quiet" or "Alert me about" according to what is actually set.
    private func menuItems(for event: SignalEvent) -> [AinkradMenuItem] {
        SignalRowMenu.items(
            for: event,
            rules: center.rules,
            sourceName: SignalPresentation.sourceLabel(event.source),
            isRead: center.readIDs.contains(event.id),
            isPinned: center.pinnedIDs.contains(event.id),
            onMuteKind: {
                SignalDeliveryMode.feedOnly.apply(to: &center.rules,
                                                  source: event.source, kind: event.kind)
            },
            onUnmuteKind: {
                SignalDeliveryMode.everything.apply(to: &center.rules,
                                                    source: event.source, kind: event.kind)
            },
            onMuteSource: {
                SignalDeliveryMode.off.apply(to: &center.rules, source: event.source)
            },
            onToggleRead: {
                if center.readIDs.contains(event.id) { center.markUnread(ids: [event.id]) }
                else { center.markRead(ids: [event.id]) }
            },
            onCopy: {
                let text = SignalRowMenu.clipboardText(
                    for: event,
                    sourceName: SignalPresentation.sourceLabel(event.source),
                    formatter: Self.clipboardFormatter)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            },
            onDismiss: { center.dismiss(ids: [event.id]) },
            onTogglePin: {
                center.setPinned(!center.pinnedIDs.contains(event.id), id: event.id)
            })
    }

    private static let clipboardFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

}
