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

    // The kit modal reports a scrim click or Esc as "no longer presented"; the
    // presenter turns that into the modal's SAFE outcome, never its primary,
    // so a stray click can never confirm anything.
    @Test func cancellingRunsTheSafeOutcomeNotThePrimary() {
        let presenter = SetupModalPresenter()
        var primaryRan = false
        var dismissRan = false
        presenter.present(modal(onPrimary: { primaryRan = true }, onDismiss: { dismissRan = true }))
        presenter.cancel()
        #expect(dismissRan)
        #expect(!primaryRan)
        #expect(presenter.modal == nil)
    }

    // Nothing up, nothing to cancel.
    @Test func cancellingWithNothingShownIsANoOp() {
        let presenter = SetupModalPresenter()
        presenter.cancel()
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
