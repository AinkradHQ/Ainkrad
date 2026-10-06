import Testing

@testable import Ainkrad

/// The wizard's blocking decisions go through one presenter. Pinned before the
/// modal moves onto the kit's `ainkradModal`, which owns the scrim and Esc.
@Suite("Setup modal presenter")
@MainActor
struct SetupModalPresenterTests {
    private func modal(onPrimary: @escaping () -> Void = {}, onDismiss: @escaping () -> Void = {})
        -> SetupModalPresenter.Modal
    {
        SetupModalPresenter.Modal(
            title: "Title", message: "Message", icon: "folder", tone: .informational,
            primaryTitle: "Use", primary: onPrimary, onDismiss: onDismiss)
    }

    @Test func presentingShowsTheModalAndDismissingClearsIt() {
        let presenter = SetupModalPresenter()
        #expect(presenter.modal == nil)
        let shown = modal()
        presenter.present(shown)
        #expect(presenter.modal?.id == shown.id)
        presenter.dismiss()
        #expect(presenter.modal == nil)
    }

    // A second decision replaces the first rather than stacking under it.
    @Test func aNewModalReplacesTheOneShowing() {
        let presenter = SetupModalPresenter()
        presenter.present(modal())
        let second = modal()
        presenter.present(second)
        #expect(presenter.modal?.id == second.id)
    }
}
