import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

/// The copy the App Store overlay shows, now that it lives off the view:
/// each error's filter-bar message and the empty grid's icon and text.
@MainActor
struct AppStoreCopyTests {
    private func store() -> AppStoreStore {
        AppStoreStore(
            service: FakeAppStoreService(), registry: BuiltInAppRegistry(persistence: InMemoryPersistenceStore()))
    }

    @Test("each App Store error has its filter-bar message")
    func errorMessages() {
        #expect(AppStoreError.download("timeout").message == "Download failed.")
        #expect(AppStoreError.checksumMismatch.message == "Integrity check failed.")
        #expect(AppStoreError.unpack("bad zip").message == "Could not unpack.")
        #expect(AppStoreError.invalidBundle("appID mismatch").message == "Invalid app bundle.")
        #expect(AppStoreError.notInstalled("hello").message == "hello is not available.")
        #expect(AppStoreError.notNewer.message == "Already up to date.")
    }

    @Test("an empty grid describes the current filter")
    func emptyStatePerFilter() {
        let s = store()
        s.filter = .all
        #expect(
            s.emptyState
                == .init(icon: "square.grid.2x2", title: "No Apps", message: "No apps available — check back later."))
        s.filter = .installed
        #expect(
            s.emptyState == .init(icon: "shippingbox", title: "Nothing Installed", message: "Nothing installed yet."))
        s.filter = .updates
        #expect(
            s.emptyState == .init(icon: "checkmark.seal", title: "Up to Date", message: "Everything is up to date."))
    }

    @Test("a search that matches nothing quotes the trimmed query, whatever the filter")
    func emptyStateForSearch() {
        let s = store()
        s.filter = .updates
        s.searchQuery = "  lore "
        #expect(s.emptyState == .init(icon: "magnifyingglass", title: "No Matches", message: "No apps match \"lore\"."))
        s.searchQuery = "   "
        #expect(s.emptyState.title == "Up to Date")
    }
}
