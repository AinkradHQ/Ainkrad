import AinkradAppKit
import AinkradHostRuntime
import AppKit
import SwiftUI
import Testing

@testable import Ainkrad

/// E5.2 sweep shots: each area's screens rendered off-screen under Neon and
/// Glass, written as `<dir>/<area>-<screen>-<theme>.png`. A tool, not a check:
/// it runs only with `AINKRAD_SWEEP_DIR` and `AINKRAD_THEMES_DIR` set
/// (`TEST_RUNNER_AINKRAD_SWEEP_DIR=<dir> make validate-themes THEMES=<catalog>/themes`)
/// and skips loudly otherwise. Off-screen capture cannot show behind-window glass.
@MainActor
@Suite("Glass sweep capture")
struct GlassSweepCaptureTests {
    private static let env = ProcessInfo.processInfo.environment

    private func shoot(
        _ name: String, size: CGSize = CGSize(width: 520, height: 320),
        _ make: (AppEnvironment) -> some View
    ) throws {
        guard let out = Self.env["AINKRAD_SWEEP_DIR"], let themes = Self.env["AINKRAD_THEMES_DIR"] else {
            print("SKIPPED: set AINKRAD_SWEEP_DIR and AINKRAD_THEMES_DIR — no sweep shot of \(name)")
            return
        }
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let runs: [(String, [String: String])] = [
            ("neon", [:]),
            ("glass", ["AinkradThemesDir": themes, "AinkradTheme": "glass", "AinkradAppearance": "dark"]),
        ]
        for (theme, arguments) in runs {
            let app = AppEnvironment.preview(launchArguments: arguments)
            let skin = app.themeManager.skin
            let view = make(app)
                .frame(width: size.width, height: size.height)
                .background(skin.color(\.background))
                .environment(app)
                .environment(\.ainkradTheme, HostThemeTokens(skin: app.themeManager.hostSkin))
                .environment(
                    \.ainkradTypography,
                    AinkradTypography(fontFamilyName: app.themeManager.uiFontFamily.fontName, scale: 1))
                .environment(\.ainkradMotionBudget, .frozen)
                .ainkradSkin(skin)
            let png = try SignalSnapshotTests.render(view, size: size)
            try png.write(to: URL(fileURLWithPath: out).appendingPathComponent("\(name)-\(theme).png"))
        }
    }

    // MARK: - Sage

    @Test("sage") func sage() throws {
        try shoot("sage-chat", size: CGSize(width: 520, height: 560)) { _ in SageRootView() }
        try shoot("sage-decision-bar", size: CGSize(width: 520, height: 90)) { _ in
            SageDecisionBar(
                content: .toolApproval(toolName: "bash", title: "Run swift test in AinkradKit"),
                actions: [
                    .init(title: "Deny", style: .ghost, perform: {}),
                    .init(title: "Approve", style: .primary, perform: {}),
                ])
        }
        try shoot("sage-diff", size: CGSize(width: 520, height: 260)) { _ in
            DiffReviewView(
                fileDiff: DiffEngine.compute(
                    old: "let a = 1\nlet b = 2\nprint(a + b)\n", new: "let a = 1\nlet b = 3\nprint(a * b)\n",
                    path: "Sources/Main.swift"),
                rejectedHunkIDs: .constant([]))
        }
        try shoot("sage-model-picker", size: CGSize(width: 360, height: 60)) { _ in
            SageConnectionModelPicker(model: SageModelPickerModel(), onManageConnections: {})
        }
    }

    // MARK: - Scry

    @Test("scry") func scry() throws {
        let elements: [(String, ScryElement)] = [
            ("text", ScryElement(id: "t", kind: .markdown, title: "Notes", body: "# Plan\n- **Ship** the sweep\n- Check `Glass`")),
            ("code", ScryElement(id: "c", kind: .code, title: "Main.swift", body: "let a = 1\nprint(a)", language: "swift")),
            ("table", ScryElement(id: "tb", kind: .table, title: "Builds", body: "| Repo | State |\n|---|---|\n| Rune | green |\n| Lore | red |")),
            ("chart", ScryElement(id: "ch", kind: .chart, title: "Tests", body: "Rune: 142\nLore: 65\nHost: 3214")),
            ("status", ScryElement(id: "s", kind: .status, title: "Build", body: "success: all green")),
            ("card", ScryElement(id: "k", kind: .card, title: "Card", body: "A card body with a little text.")),
        ]
        for (name, element) in elements {
            try shoot("scry-\(name)", size: CGSize(width: 480, height: 240)) { _ in
                ScryElementView(element: element).padding()
            }
        }
    }

    // MARK: - Signal

    @Test("signal") func signal() throws {
        let now = Date()
        let events = [
            SignalEvent(
                timestamp: now.addingTimeInterval(-25), source: .app(appID: "com.ainkrad.raven"), kind: "build.failed",
                severity: .failure, title: "Build failed", body: "3 errors in SignalStore.swift",
                actions: [SignalAction(id: "rerun", label: "Re-run")], dedupeKey: "b:main"),
            SignalEvent(
                timestamp: now.addingTimeInterval(-240), source: .app(appID: "com.ainkrad.quest"),
                kind: "session.needs-input", severity: .warning, title: "Quest is waiting for you",
                body: "The agent paused for approval."),
            SignalEvent(
                timestamp: now.addingTimeInterval(-3600), source: .host, kind: "run.finished", severity: .success,
                title: "Run finished", body: "Wrote 4 articles"),
        ]
        try shoot("signal-bell-dropdown", size: CGSize(width: 420, height: 380)) { _ in
            SignalBellDropdown(events: events, unread: 2, now: now).padding()
        }
        try shoot("signal-toasts", size: CGSize(width: 420, height: 300)) { _ in
            let model = SignalToastModel()
            for event in events.reversed() { model.present(event) }
            return SignalToastStack(model: model, now: now, onActivate: { _ in }).padding()
        }
        try shoot("signal-banner", size: CGSize(width: 420, height: 90)) { _ in
            AinkradBanner(message: "Connection restored", status: .neutral, onDismiss: {}).padding()
        }
    }

    // MARK: - Hoard

    @Test("hoard") func hoard() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sweep-hoard", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("notes.md")
        try "# Notes\nSome text.".write(to: file, atomically: true, encoding: .utf8)
        let entry = FileEntry(
            url: file, name: "notes.md", isDirectory: false, isSymlink: false, isHidden: false, size: 18,
            modified: Date(timeIntervalSince1970: 0))
        try shoot("hoard-preview", size: CGSize(width: 320, height: 420)) { _ in PreviewPane(entry: entry, itemCount: 3) }
        try shoot("hoard-prompt-rename", size: CGSize(width: 420, height: 220)) { _ in
            HoardPromptSheet(prompt: .rename(entry), onCancel: {}, onRename: { _, _ in }, onNewFolder: { _ in })
        }
        try shoot("hoard-breadcrumb-edit", size: CGSize(width: 520, height: 60)) { app in
            HoardBreadcrumbBar(
                tab: HoardTab(directory: dir, fileSystem: app.filesSystemService), fileSystem: app.filesSystemService,
                isEditing: .constant(true))
        }
        try shoot("hoard-operations", size: CGSize(width: 420, height: 200)) { app in
            OperationsPanel(engine: app.filesOperationEngine)
        }
    }

    // MARK: - Setup

    @Test("setup") func setup() throws {
        try shoot("setup-welcome", size: CGSize(width: 900, height: 640)) { _ in SetupOverlayView() }
    }

    // MARK: - Settings

    @Test("settings") func settings() throws {
        try shoot("settings-overlay", size: CGSize(width: 900, height: 640)) { _ in SettingsOverlayView(onDismiss: {}) }
        try shoot("settings-status-bar", size: CGSize(width: 900, height: 40)) { _ in
            FullScreenStatusBarView(monitor: SystemStatusMonitor())
        }
        try shoot("settings-confirm", size: CGSize(width: 520, height: 320)) { _ in
            Color.clear.ainkradConfirmDialog(
                isPresented: .constant(true), title: "Delete workspace?", message: "This cannot be undone.",
                confirmTitle: "Delete", isDestructive: true, onConfirm: {})
        }
    }
}
