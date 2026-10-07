import Foundation

/// A single active background run as the menu-bar popover shows it.
struct MenuBarRunItem: Equatable, Identifiable {
    let id: UUID
    let title: String
    let isActive: Bool  // running (true) vs queued/paused (false)
}

/// Seam over Slice-3 `RunManager`. Keeps the menu-bar subsystem compiling and
/// testable without a hard dependency on the (PROVISIONAL) RunManager type.
@MainActor
protocol MenuBarRunSource: AnyObject {
    var activeRunItems: [MenuBarRunItem] { get }
    func stopRun(_ id: UUID)
}

/// Adapts the real Slice-3 `RunManager` (queue + active/running set) onto the
/// menu-bar's `MenuBarRunSource` seam: `RunManager.active` already covers
/// `.queued`/`.running`/`.paused`, so `isActive` distinguishes "actually
/// running" from "still waiting a slot".
@MainActor
final class RunManagerMenuBarAdapter: MenuBarRunSource {
    private let manager: RunManager
    init(manager: RunManager) { self.manager = manager }
    var activeRunItems: [MenuBarRunItem] {
        manager.active.map {
            MenuBarRunItem(id: $0.id, title: $0.prompt, isActive: $0.status == .running)
        }
    }
    func stopRun(_ id: UUID) { manager.stop(id) }
}
