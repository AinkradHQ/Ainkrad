import Foundation

@testable import Ainkrad

/// A run source that reports no runs and stops nothing — the menu-bar tests'
/// stand-in for `RunManagerMenuBarAdapter`.
@MainActor
final class EmptyMenuBarRunSource: MenuBarRunSource {
    var activeRunItems: [MenuBarRunItem] { [] }
    func stopRun(_ id: UUID) {}
}
