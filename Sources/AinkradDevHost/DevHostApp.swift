import AinkradAppKitUI
import SwiftUI

/// Dev-only host that loads and renders a developer's plugin bundle through
/// the shared `AinkradHostRuntime` — the same validation and load path the
/// real host and store review use, so what a developer sees here matches
/// what ships. The window composes the plugin stage with a validation
/// banner (green on load, red with the exact rejection message) and a log
/// pane tailing both that lifecycle and the plugin subsystem's real os_log
/// output — see `ValidationBanner`, `LogPaneView`, `LogTail`.
@main
struct DevHostApp: App {
    /// The plugin subsystem `AinkradHostRuntime.Log` logs under — see that
    /// module's `Log.swift`. `LogTail` reads this via `OSLogStore`.
    private static let pluginSubsystem = "com.ainkrad.app"

    @Environment(\.ainkradSkin) private var skin
    @State private var model = DevHostModel()
    @State private var logTail: LogTail
    private let lifecycleEvents: AsyncStream<LogTail.LifecycleEvent>.Continuation

    init() {
        let (stream, continuation) = AsyncStream<LogTail.LifecycleEvent>.makeStream()
        lifecycleEvents = continuation
        _logTail = State(initialValue: LogTail(lifecycleEvents: stream))
    }

    var body: some Scene {
        WindowGroup("Ainkrad Dev Host") {
            VStack(spacing: 0) {
                // Shown only with a plugin on the stage: with nothing loaded
                // there are no surfaces to choose between, and a live picker
                // over a placeholder invites the reading that the bundle
                // loaded and its settings are simply blank.
                if case .loaded = model.state {
                    AinkradSegmentedPicker(
                        items: DevHostModel.Surface.allCases, selection: $model.surface,
                        label: { $0 == .root ? "App" : "Settings" }
                    )
                    .fixedSize()
                    .padding(skin.size.s6)
                }
                PluginStageView(state: model.state, surface: model.surface)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                ValidationBanner(state: model.state)
                LogPaneView(logTail: logTail, subsystem: Self.pluginSubsystem)
                    .frame(height: skin.size.s160)
            }
            .onAppear {
                guard case .empty = model.state else { return }
                switch LaunchArguments.parse(Array(CommandLine.arguments.dropFirst())) {
                case .success(let args):
                    model.load(args)
                    switch model.state {
                    case .loaded(let app):
                        lifecycleEvents.yield(.loaded(app.id))
                    case .invalid(let message):
                        lifecycleEvents.yield(.rejected(reason: message))
                    case .empty:
                        break
                    }
                case .failure:
                    // No/invalid --bundle: leave `.empty` — this is a
                    // dev-only host, not a crash-worthy condition.
                    break
                }
            }
        }
        .defaultSize(width: 800, height: 600)
    }
}
