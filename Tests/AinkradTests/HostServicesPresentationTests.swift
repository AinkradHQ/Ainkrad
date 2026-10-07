import AinkradAppKit
import AinkradHostRuntime
import Testing

@testable import Ainkrad

@MainActor
struct HostServicesPresentationTests {
    @Test("current returns declared default until overridden, then the override; reset clears")
    func presentationControl() {
        let store = AppAppearanceStore(persistence: InMemoryPersistenceStore())
        let control = HostPresentationControl(appID: "x", declaredDefault: .overlay, store: store)
        #expect(control.current == .overlay)
        control.set(.pane)
        #expect(control.current == .pane)
        #expect(store.presentationOverride("x") == .pane)
        control.reset()
        #expect(control.current == .overlay)
    }
}
