import Foundation
import Testing

@testable import Ainkrad

/// `finalizeBootstrap` is an orchestrator over two phases, and their order is part
/// of the wiring contract: the apps phase reports plugin load failures into the feed
/// the signal phase builds. The phases record themselves in DEBUG, so a future
/// reorder fails here rather than silently changing boot.
@Suite("Bootstrap phase order")
@MainActor
struct BootstrapPhaseOrderTests {
    @Test func finalizeRunsTheSignalPhaseBeforeTheAppsPhase() {
        let t = TestHome.make("phase-order")
        defer { t.cleanup() }

        _ = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        #expect(AppEnvironment.finalizePhaseLog == ["signal", "apps"])
    }
}
