import Testing
import SwiftUI
import AppKit
import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal
@testable import Ainkrad

/// Renders Signal surfaces to PNG so they can be looked at during review.
///
/// `ImageRenderer`, not `screencapture`: a window-server capture photographs
/// whatever is being composited at that instant, so a shot taken during an
/// animation or with another window in front comes back wrong and looks like a
/// rendering bug rather than a capture bug. Rendering the view directly is
/// deterministic and needs no window at all.
///
/// Disabled by default - it writes files and exists for the reviewer, not for
/// CI. Run it with `SIGNAL_SNAPSHOT_DIR=/some/dir`.
@MainActor
@Suite("Signal snapshots", .enabled(if: ProcessInfo.processInfo.environment["SIGNAL_SNAPSHOT_DIR"] != nil))
struct SignalSnapshotTests {
    private var outputDirectory: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["SIGNAL_SNAPSHOT_DIR"]!,
            isDirectory: true)
    }

    private func sampleEvents(now: Date) -> [SignalEvent] {
        [
            SignalEvent(timestamp: now.addingTimeInterval(-25), source: .app(appID: "com.ainkrad.raven"),
                        kind: "build.failed", severity: .failure,
                        title: "Build failed",
                        body: "3 errors in SignalStore.swift - linker could not resolve _sqlite3_open",
                        actions: [SignalAction(id: "rerun", label: "Re-run"),
                                  SignalAction(id: "open", label: "Open log")],
                        dedupeKey: "b:main"),
            SignalEvent(timestamp: now.addingTimeInterval(-240), source: .app(appID: "com.ainkrad.quest"),
                        kind: "session.needs-input", severity: .warning,
                        title: "Quest is waiting for you",
                        body: "The agent paused for approval before running a destructive command."),
            SignalEvent(timestamp: now.addingTimeInterval(-3600), source: .host,
                        kind: "run.finished", severity: .success,
                        title: "Run finished",
                        body: "harvest the vault into Wiki articles\nWrote 4 articles, 1 skipped"),
            SignalEvent(timestamp: now.addingTimeInterval(-7200), source: .sage,
                        kind: "memory.indexed", severity: .info,
                        title: "Memory index rebuilt", body: "1,204 notes indexed in 2.1s"),
            SignalEvent(timestamp: now.addingTimeInterval(-90000), source: .app(appID: "com.ainkrad.lore"),
                        kind: "index.completed", severity: .info,
                        title: "Vault index completed"),
        ]
    }

    @Test("render the feed list")
    func renderFeedList() throws {
        let now = Date()
        let events = sampleEvents(now: now)
        let theme = Theme.neonBlue

        let view = SignalFeedList(
            events: events,
            repeatCounts: [events[0].id: 4],
            readIDs: [events[3].id, events[4].id],
            now: now)
            .frame(width: 380, height: 420)
            .background(HostThemeTokens(from: theme).surface)
            .environment(\.ainkradTheme, HostThemeTokens(from: theme))
            .environment(\.ainkradTypography, Self.hostTypography)
            .environment(\.ainkradStatusColors, AinkradStatusColors(
                success: theme.tokens.success,
                warning: theme.tokens.warning,
                danger: theme.tokens.danger))

        let png = try Self.render(view, size: CGSize(width: 380, height: 420))
        let url = outputDirectory.appendingPathComponent("signal-feed-list.png")
        try png.write(to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("render the top-bar bell")
    func renderTopBarBell() throws {
        let theme = Theme.neonBlue
        let tokens = theme.tokens

        // The bell as it sits in HUDBar: floating on the sky beside the
        // workspace diamonds, with the readout chips to its left for scale.
        let view = HStack(spacing: 12) {
            Text("3:32 PM").font(AinkradFont.mono(11, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.85))
            Text("Tue, 1 Sep").font(AinkradFont.mono(11, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.5))
            Spacer()
            SignalBellButton(unread: 3, tokens: tokens) {}
            HStack(spacing: 8) {
                ChevronMark().fill(tokens.accentSecondary).frame(width: 10, height: 8.5)
                Rectangle().fill(tokens.foreground.opacity(0.28))
                    .frame(width: 5, height: 5).rotationEffect(.degrees(45))
            }
        }
            .padding(.horizontal, 14)
            .frame(width: 620, height: 30)
            .background(HostThemeTokens(from: theme).background)
            .environment(\.ainkradTheme, HostThemeTokens(from: theme))

        let png = try Self.render(view, size: CGSize(width: 620, height: 30))
        try png.write(to: outputDirectory.appendingPathComponent("signal-topbar-bell.png"))
    }

    @Test("render the bell dropdown")
    func renderBellDropdown() throws {
        let now = Date()
        let events = sampleEvents(now: now)
        let theme = Theme.neonBlue

        // Shown over a sky-toned ground with the top bar above it, so the
        // panel's chrome and its position under the bell are both visible.
        let view = ZStack(alignment: .topTrailing) {
            HostThemeTokens(from: theme).background
            HStack(spacing: 12) {
                Text("3:32 PM").font(AinkradFont.mono(11, weight: .medium))
                    .foregroundStyle(theme.tokens.foreground.opacity(0.85))
                Spacer()
                SignalBellButton(unread: 3, tokens: theme.tokens) {}
                HStack(spacing: 8) {
                    ChevronMark().fill(theme.tokens.accentSecondary).frame(width: 10, height: 8.5)
                    Rectangle().fill(theme.tokens.foreground.opacity(0.28))
                        .frame(width: 5, height: 5).rotationEffect(.degrees(45))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
            .frame(maxHeight: .infinity, alignment: .top)

            SignalBellDropdown(
                events: events,
                unread: 3,
                repeatCounts: [events[0].id: 4],
                readIDs: [events[3].id, events[4].id],
                now: now)
                .padding(.top, 34)
                .padding(.trailing, 10)
        }
            .frame(width: 560, height: 470)
            .environment(\.ainkradTheme, HostThemeTokens(from: theme))
            .environment(\.ainkradTypography, Self.hostTypography)
            .environment(\.ainkradStatusColors, AinkradStatusColors(
                success: theme.tokens.success,
                warning: theme.tokens.warning,
                danger: theme.tokens.danger))

        let png = try Self.render(view, size: CGSize(width: 560, height: 470))
        try png.write(to: outputDirectory.appendingPathComponent("signal-dropdown.png"))
    }

    @Test("render the feed overlay")
    func renderFeedOverlay() throws {
        let now = Date()
        let theme = Theme.neonBlue
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("signal-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        // The REAL overlay, not the island in isolation: the island has no
        // background of its own by design (the hosting `AinkradPanel` supplies
        // the glass), so rendering it bare shows light text on nothing.
        let center = SignalCenter(store: try SignalStore(url: url),
                                  deliverer: SnapshotDeliverer(), contextProvider: SnapshotContext())
        for event in sampleEvents(now: now).reversed() {
            center.emit(SignalDraft(kind: event.kind, severity: event.severity,
                                    title: event.title, body: event.body,
                                    actions: event.actions,
                                    dedupeKey: event.dedupeKey), from: event.source)
        }
        // Coalesce the build failure so the xN badge renders, and read the two
        // oldest rows so unread dots are not uniformly on.
        center.emit(SignalDraft(kind: "build.failed", severity: .failure,
                                title: "Build failed", dedupeKey: "b:main"), from: .app(appID: "com.ainkrad.raven"))
        center.markRead(ids: Array(center.recent.suffix(2).map(\.id)))

        let view = ZStack {
            HostThemeTokens(from: theme).background
            SignalFeedOverlayView(center: center, onDismiss: {})
        }
            // Wider than the island's own 820, so the source rail is inside
            // the frame. A snapshot that clips the thing it was taken to show
            // still passes and still tells you nothing.
            .frame(width: 940, height: 660)
            .environment(\.ainkradTheme, HostThemeTokens(from: theme))
            .environment(\.ainkradTypography, Self.hostTypography)
            .environment(\.ainkradStatusColors, AinkradStatusColors(
                success: theme.tokens.success,
                warning: theme.tokens.warning,
                danger: theme.tokens.danger))

        let png = try Self.render(view, size: CGSize(width: 940, height: 660))
        try png.write(to: outputDirectory.appendingPathComponent("signal-feed-overlay.png"))
    }

    @Test("render the feed grouped by app, with a burst collapsed")
    func renderGroupedFeed() throws {
        let now = Date()
        let theme = Theme.neonBlue
        let raven = SignalSource.app(appID: "com.ainkrad.raven")
        // Nineteen identical warnings is the real shape this mode exists for —
        // it is what a Raven sync loop actually produces, and reading it as
        // nineteen rows is the problem grouping solves.
        var events: [SignalEvent] = (1...19).map { i in
            SignalEvent(timestamp: now.addingTimeInterval(-Double(i)), source: raven,
                        kind: "sync.failed", severity: .warning,
                        title: "Sync failed", body: "attempt \(i)")
        }
        events.append(SignalEvent(timestamp: now, source: .sage, kind: "index.rebuilt",
                                  severity: .info, title: "Memory index rebuilt"))

        let groups = SignalPresentation.sourceGroups(
            events, readIDs: [], name: { SignalPresentation.sourceLabel($0) })
        let collapsed = Binding.constant(Set([groups.first(where: {
            $0.name == "Raven" })?.id ?? ""]))

        let view = ZStack {
            HostThemeTokens(from: theme).background
            AinkradPanel(showsBrackets: true) {
                SignalFeedGroupedList(groups: groups, collapsed: collapsed, now: now)
                    .frame(width: 620, height: 380)
            }
        }
            .frame(width: 700, height: 460)
            .environment(\.ainkradTheme, HostThemeTokens(from: theme))
            .environment(\.ainkradTypography, Self.hostTypography)
            .environment(\.ainkradStatusColors, AinkradStatusColors(
                success: theme.tokens.success,
                warning: theme.tokens.warning,
                danger: theme.tokens.danger))

        let png = try Self.render(view, size: CGSize(width: 700, height: 460))
        try png.write(to: outputDirectory.appendingPathComponent("signal-feed-grouped.png"))
    }

    @Test("render a source's notification sheet, with its kinds")
    func renderSourceSheet() throws {
        let theme = Theme.neonBlue
        var rules = RoutingRules.default
        let raven = SignalSource.app(appID: "com.ainkrad.raven")
        rules.interruptFloor[raven] = .warning
        SignalDeliveryMode.feedOnly.apply(to: &rules, source: raven, kind: "sync.failed")

        let view = ZStack {
            HostThemeTokens(from: theme).background
            AinkradPanel(showsBrackets: true) {
                SourceNotificationSheet(
                    source: raven, sourceName: "Raven",
                    rules: .constant(rules),
                    // Noisiest first, which is the row the user came to find.
                    activity: [
                        SignalKindActivity(kind: "sync.failed", count: 19, lastSeen: Date()),
                        SignalKindActivity(kind: "build.failed", count: 4, lastSeen: Date()),
                        SignalKindActivity(kind: "index.rebuilt", count: 1, lastSeen: Date()),
                    ])
                .frame(width: 520)
                .padding(AinkradSpacing.md)
            }
        }
            .frame(width: 620, height: 640)
            .environment(\.ainkradTheme, HostThemeTokens(from: theme))
            .environment(\.ainkradTypography, Self.hostTypography)
            .environment(\.ainkradStatusColors, AinkradStatusColors(
                success: theme.tokens.success, warning: theme.tokens.warning,
                danger: theme.tokens.danger))

        let png = try Self.render(view, size: CGSize(width: 620, height: 640))
        try png.write(to: outputDirectory.appendingPathComponent("signal-source-sheet.png"))
    }

    @Test("render the toast stack")
    func renderToastStack() throws {
        let now = Date()
        let events = sampleEvents(now: now)
        let theme = Theme.neonBlue
        let model = SignalToastModel()
        // Five arrivals against a cap of three, so the overflow chip renders.
        // Presented oldest-first, the order they would actually arrive in, so
        // the newest ends up on top as it would at runtime.
        for event in events.prefix(5).reversed() { model.present(event) }

        let view = ZStack(alignment: .topTrailing) {
            HostThemeTokens(from: theme).background
            HStack {
                Spacer()
                SignalBellButton(unread: 3, tokens: theme.tokens) {}
                    .padding(.trailing, 14)
            }
            .frame(height: 30)
            .frame(maxHeight: .infinity, alignment: .top)
            SignalToastStack(model: model, now: now)
                .padding(.top, 34)
        }
            .frame(width: 420, height: 340)
            .environment(\.ainkradTheme, HostThemeTokens(from: theme))
            .environment(\.ainkradTypography, Self.hostTypography)
            .environment(\.ainkradStatusColors, AinkradStatusColors(
                success: theme.tokens.success,
                warning: theme.tokens.warning,
                danger: theme.tokens.danger))

        let png = try Self.render(view, size: CGSize(width: 420, height: 340))
        try png.write(to: outputDirectory.appendingPathComponent("signal-toasts.png"))
    }

    @Test("render the notifications settings pane")
    func renderSettingsPane() throws {
        let now = Date()
        let theme = Theme.neonBlue
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("signal-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        final class NullDeliverer: SignalDeliverer {
            func deliver(_ event: SignalEvent, to channels: Set<DeliveryChannel>) {}
        }
        struct Ctx: SignalContextProviding {
            var deliveryContext = DeliveryContext(hostIsFrontmost: true, visibleAppIDs: [],
                                                  systemDoNotDisturb: false, hostFocusMode: false)
        }
        let center = SignalCenter(store: try SignalStore(url: url),
                                  deliverer: NullDeliverer(), contextProvider: Ctx())
        for event in sampleEvents(now: now) {
            center.emit(SignalDraft(kind: event.kind, severity: event.severity,
                                    title: event.title, body: event.body), from: event.source)
        }
        // Enough configured state that the pane is not all defaults: one
        // source off, one with per-kind overrides and a floor, so the status
        // lines under the rows actually render.
        center.rules.mutedSources.insert(.sage)
        SignalDeliveryMode.feedOnly.apply(to: &center.rules,
                                          source: .app(appID: "com.ainkrad.raven"),
                                          kind: "build.failed")
        center.rules.interruptFloor[.app(appID: "com.ainkrad.raven")] = .warning
        center.rules.urgentBypass.insert(.app(appID: "com.ainkrad.quest"))

        let view = SignalSettingsPane(
            center: center,
            sources: [.host, .sage,
                      .app(appID: "com.ainkrad.raven"), .app(appID: "com.ainkrad.quest")],
            // Real names, as the live pane supplies. Without it the rows read
            // as raw bundle ids and wrap, which is a property of the snapshot
            // rather than of the pane.
            displayName: { $0.split(separator: ".").last.map(String.init)?.capitalized ?? $0 })
            .padding(16)
            .frame(width: 560, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(HostThemeTokens(from: theme).background)
            .environment(\.ainkradTheme, HostThemeTokens(from: theme))
            .environment(\.ainkradTypography, Self.hostTypography)
            .environment(\.ainkradStatusColors, AinkradStatusColors(
                success: theme.tokens.success,
                warning: theme.tokens.warning,
                danger: theme.tokens.danger))

        // Tall enough for the WHOLE pane. At 660 the content overflowed its
        // frame and the capture began part-way down, so the snapshot silently
        // omitted the first three panels — including the caption that defines
        // the vocabulary every control below it uses.
        let png = try Self.render(view, size: CGSize(width: 560, height: 1500))
        try png.write(to: outputDirectory.appendingPathComponent("signal-settings.png"))
    }

    @Test("render the launcher tiles with unread badges")
    func renderLauncherBadges() throws {
        let theme = Theme.neonBlue
        let tokens = theme.tokens

        // Tiles at both sizes the launcher uses (32 list, 46 grid), badged and
        // unbadged side by side, so the badge's effect on the footprint is
        // visible — it must not nudge its neighbours.
        let view = HStack(spacing: 22) {
            NeonAppTile(symbol: "terminal", tokens: tokens, size: 46, badge: "3")
            NeonAppTile(symbol: "sparkles", tokens: tokens, size: 46)
            NeonAppTile(symbol: "hammer", tokens: tokens, size: 46, badge: "99+")
            NeonAppTile(symbol: "book", tokens: tokens, size: 32, badge: "1")
            NeonAppTile(symbol: "arrow.triangle.branch", tokens: tokens, size: 32)
        }
            .padding(26)
            .frame(width: 420, height: 100)
            .background(HostThemeTokens(from: theme).background)
            .environment(\.ainkradTheme, HostThemeTokens(from: theme))
            .environment(\.ainkradTypography, Self.hostTypography)

        let png = try Self.render(view, size: CGSize(width: 420, height: 100))
        try png.write(to: outputDirectory.appendingPathComponent("signal-launcher-badges.png"))
    }

    /// The typography the running app injects (`AinkradApp` sets
    /// `fontFamilyName` from `themeManager.uiFontFamily`), not
    /// `AinkradTypography.default` — whose `fontFamilyName` is nil, which falls
    /// back to the SYSTEM face.
    ///
    /// This mattered: after the feed components moved into the kit they resolve
    /// type through `AinkradFontResolver`, which reads this environment value,
    /// where before they used the host's `AinkradFont` and its statically
    /// configured family. A harness passing `.default` therefore rendered the
    /// brand face before the move and the system face after it, and the
    /// snapshot diff blamed the move for a defect in the harness.
    static let hostTypography = AinkradTypography(
        fontFamilyName: UIFontFamily.exo2.fontName, scale: 1.0)

    /// Renders through a real `NSHostingView` in an offscreen window.
    ///
    /// `ImageRenderer` was the first choice and produced a blank image: it does
    /// not materialise `ScrollView`/`LazyVStack` content, which is most of what
    /// this surface is. Hosting the view for real and asking the layer to draw
    /// itself renders the actual hierarchy, and still needs no visible window
    /// and no window-server capture.
    static func render(_ view: some View, size: CGSize) throws -> Data {
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(contentRect: hosting.frame,
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.setIsVisible(false)

        // SwiftUI lays out on the run loop, so give it turns to settle before
        // drawing; without this the lazy rows are still unbuilt.
        hosting.layoutSubtreeIfNeeded()
        for _ in 0..<8 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            hosting.layoutSubtreeIfNeeded()
        }

        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds),
                               "could not create a bitmap rep")
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return try #require(rep.representation(using: .png, properties: [:]),
                            "could not encode PNG")
    }
    // MARK: - Generation 10: subscription approval

    /// What the host's registry would answer.
    private static let sampleDisplayNames: (String) -> String = { appID in
        ["raven": "Raven", "quest": "Quest", "lore": "Lore",
         "gitmage": "Git Mage", "leyline": "Leyline"][appID] ?? appID
    }

    /// Shared chrome for the three generation-10 snapshots.
    private func themed<V: View>(_ view: V, width: CGFloat) -> some View {
        let theme = Theme.neonBlue
        return view
            .frame(width: width)
            .padding(28)
            // Fill whatever canvas the caller asked for BEFORE painting the
            // background. Without this the background only covers the
            // content's intrinsic size, and any canvas taller than the content
            // came back with an unpainted white band across the top — which
            // reads as a rendering bug in the panel rather than as a snapshot
            // that was sized wrong.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(HostThemeTokens(from: theme).background)
            .environment(\.ainkradTheme, HostThemeTokens(from: theme))
            .environment(\.ainkradTypography, Self.hostTypography)
            .environment(\.ainkradStatusColors, AinkradStatusColors(
                success: theme.tokens.success,
                warning: theme.tokens.warning,
                danger: theme.tokens.danger))
    }

    private func writeSnapshot<V: View>(_ view: V, size: CGSize, named name: String) throws {
        let png = try Self.render(view, size: size)
        let url = outputDirectory.appendingPathComponent(name)
        try png.write(to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("render the subscription approval prompt")
    func renderApprovalPrompt() throws {
        let view = themed(SubscriptionApprovalView(
            appName: "Git Mage",
            subscriptions: SignalSubscription.parse([
                "app:raven/build.*",
                "host/run.finished",
                "sage/*",
            ]),
            displayName: Self.sampleDisplayNames), width: 420)
        try writeSnapshot(view, size: CGSize(width: 476, height: 440),
                          named: "subscription-approval.png")
    }

    @Test("render the re-approval prompt, which must explain itself")
    func renderReapprovalPrompt() throws {
        let view = themed(SubscriptionApprovalView(
            appName: "Git Mage",
            subscriptions: SignalSubscription.parse([
                "app:raven/build.*",
                "app:quest/work.*",
                "host/run.finished",
                "sage/*",
            ]),
            displayName: Self.sampleDisplayNames,
            isReapproval: true), width: 420)
        try writeSnapshot(view, size: CGSize(width: 476, height: 500),
                          named: "subscription-reapproval.png")
    }

    @Test("render the settings section, showing an allowed and a refused app")
    func renderSettingsSection() throws {
        let view = themed(SubscriptionSettingsSection(rows: [
            .init(id: "gitmage", appName: "Git Mage",
                  subscriptions: SignalSubscription.parse(["app:raven/build.*",
                                                           "host/run.finished"]),
                  isApproved: true),
            .init(id: "leyline", appName: "Leyline",
                  subscriptions: SignalSubscription.parse(["sage/*"]),
                  isApproved: false),
        ], displayName: Self.sampleDisplayNames), width: 420)
        try writeSnapshot(view, size: CGSize(width: 476, height: 360),
                          named: "subscription-settings.png")
    }

}

@MainActor
private final class SnapshotDeliverer: SignalDeliverer {
    func deliver(_ event: SignalEvent, to channels: Set<DeliveryChannel>) {}
}
private struct SnapshotContext: SignalContextProviding {
    var deliveryContext = DeliveryContext(hostIsFrontmost: true, visibleAppIDs: [],
                                          systemDoNotDisturb: false, hostFocusMode: false)
}
