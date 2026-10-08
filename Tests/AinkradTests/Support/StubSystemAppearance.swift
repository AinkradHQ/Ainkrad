import AinkradHostRuntime

/// A `SystemAppearanceSource` a test flips by hand; setting `current` notifies.
@MainActor
final class StubSystemAppearance: SystemAppearanceSource {
    private var handler: (@MainActor () -> Void)?

    var current: ThemeAppearance {
        didSet { handler?() }
    }

    init(_ current: ThemeAppearance = .dark) { self.current = current }

    func observe(_ handler: @escaping @MainActor () -> Void) { self.handler = handler }
}
