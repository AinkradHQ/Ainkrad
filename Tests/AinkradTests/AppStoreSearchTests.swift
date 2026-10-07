import Testing

@testable import Ainkrad

/// TDD for AIN-148: the App Store search field's match predicate.
/// `AppStoreStore.matches` is a pure function so it can be unit-tested
/// without spinning up a store/service/registry.
@MainActor
struct AppStoreSearchTests {
    private func row(
        name: String = "Terminal", description: String = "A shell",
        author: String? = "Ainkrad"
    ) -> AppStoreRow {
        AppStoreRow(
            id: "terminal", displayName: name, icon: "terminal", description: description,
            catalogVersion: nil, installedVersion: "1.0.0", status: .installed,
            isEnabled: true, kind: .builtIn, isManaged: false, author: author)
    }

    @Test("empty query matches everything")
    func emptyQueryMatchesAll() {
        #expect(AppStoreStore.matches(row(), query: ""))
    }

    @Test("whitespace-only query is treated as empty and matches everything")
    func whitespaceQueryMatchesAll() {
        #expect(AppStoreStore.matches(row(), query: "   "))
    }

    @Test("case-insensitive match on displayName")
    func matchesDisplayNameCaseInsensitively() {
        #expect(AppStoreStore.matches(row(name: "Terminal"), query: "TERM"))
    }

    @Test("match on description")
    func matchesDescription() {
        #expect(AppStoreStore.matches(row(description: "A cozy shell app"), query: "cozy"))
    }

    @Test("match on author")
    func matchesAuthor() {
        #expect(AppStoreStore.matches(row(author: "Ahmed"), query: "ahmed"))
    }

    @Test("query matching nothing returns false")
    func nonMatchReturnsFalse() {
        #expect(!AppStoreStore.matches(row(name: "Terminal", description: "A shell", author: "Ahmed"), query: "notes"))
    }

    @Test("a row with no author does not match on author, but query still isn't found")
    func nilAuthorDoesNotCrash() {
        #expect(!AppStoreStore.matches(row(author: nil), query: "ahmed"))
    }
}
