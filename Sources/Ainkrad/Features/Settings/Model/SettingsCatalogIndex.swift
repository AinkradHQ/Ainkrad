import AinkradAppKitContract
import Foundation

/// A single hit in a settings search. `valueDescription` shows the live
/// value inline — often the value is the whole reason someone searched — but
/// is deliberately `nil` for anything with no safe or meaningful value to
/// show (`.secure`, `.action`, `.custom`).
struct SettingsSearchResult: Identifiable {
    let path: SettingsPath
    let label: String
    /// "Intelligence › Permissions & Sandbox"
    let breadcrumb: String
    let valueDescription: String?
    let score: Int

    var id: SettingsPath { path }
}

/// The settings search index. Built from the catalog at launch and rebuilt
/// when apps are enabled or disabled. Every field in the catalog is
/// guaranteed to appear in `indexedPaths` — see the coverage-guard test.
@MainActor
struct SettingsCatalogIndex {
    private struct Entry {
        let path: SettingsPath
        let label: String
        let breadcrumb: String
        let pagePath: SettingsPath
        let haystack: Haystack
        let valueDescription: String?
    }

    /// Each tier is matched separately so ranking can tell them apart.
    private struct Haystack {
        let label: String
        let keywords: [String]
        let help: String
        let titles: String
        let optionTitles: [String]
    }

    private let entries: [Entry]

    var indexedPaths: Set<SettingsPath> { Set(entries.map(\.path)) }

    init(catalog: SettingsCatalog) {
        entries = catalog.pages.flatMap { page in
            page.groups.flatMap { group in
                group.fields.map { field in
                    Entry(
                        path: field.path,
                        label: field.label,
                        breadcrumb: "\(page.title) › \(group.title)",
                        pagePath: page.path,
                        haystack: Haystack(
                            label: field.label.lowercased(),
                            keywords: field.keywords.map { $0.lowercased() },
                            help: (field.help ?? "").lowercased(),
                            titles: "\(page.title) \(group.title)".lowercased(),
                            optionTitles: Self.optionTitles(field.kind).map { $0.lowercased() }),
                        valueDescription: Self.valueDescription(field.kind))
                }
            }
        }
    }

    func search(_ query: String, currentPage: SettingsPath?) -> [SettingsSearchResult] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return [] }
        let terms = needle.split(separator: " ").map(String.init)

        let results = entries.compactMap { entry -> SettingsSearchResult? in
            guard let base = score(entry: entry, needle: needle, terms: terms) else { return nil }
            let boost = (currentPage != nil && entry.pagePath == currentPage) ? 5 : 0
            return SettingsSearchResult(
                path: entry.path, label: entry.label, breadcrumb: entry.breadcrumb,
                valueDescription: entry.valueDescription, score: base + boost)
        }
        // Sort is total (score, then label, then the path's own string form)
        // so equal-score results never land in a run-to-run-unstable order.
        return results.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.label != $1.label { return $0.label < $1.label }
            return $0.path.rawValue < $1.path.rawValue
        }
    }

    func matchedPaths(_ query: String, on page: SettingsPage) -> Set<SettingsPath> {
        let hits = search(query, currentPage: nil).map(\.path)
        return Set(page.allFields.map(\.path)).intersection(hits)
    }

    /// Ranking tiers, highest first. Returns `nil` for no match at all.
    private func score(entry: Entry, needle: String, terms: [String]) -> Int? {
        let hay = entry.haystack
        if hay.label == needle { return 100 }
        if hay.label.hasPrefix(needle) { return 80 }
        if Self.matchesWordBoundary(hay.label, needle) { return 60 }
        if hay.keywords.contains(where: { $0.contains(needle) }) { return 45 }
        if hay.optionTitles.contains(where: { $0.contains(needle) }) { return 40 }
        if hay.help.contains(needle) { return 25 }
        if hay.titles.contains(needle) { return 15 }
        // Multi-word queries ("assistant blur", "tools mcp") match across
        // label + page/group titles + keywords + help, so a query that
        // spans a field's own text and its breadcrumb still resolves.
        if terms.count > 1 {
            let combined = "\(hay.label) \(hay.titles) \(hay.keywords.joined(separator: " ")) \(hay.help)"
            if terms.allSatisfy({ combined.contains($0) }) { return 10 }
        }
        return nil
    }

    private static func matchesWordBoundary(_ haystack: String, _ needle: String) -> Bool {
        haystack.split(separator: " ").contains { $0.hasPrefix(needle) }
    }

    private static func optionTitles(_ kind: SettingsFieldKind) -> [String] {
        if case .select(let options, _) = kind { return options.map(\.title) }
        return []
    }

    /// Never surface a secret. `.secure` fields (API keys, tokens) MUST
    /// return `nil` here — the search index must not render a credential
    /// into a result. `.action` and `.custom` have no meaningful single
    /// value either.
    private static func valueDescription(_ kind: SettingsFieldKind) -> String? {
        switch kind {
        case .toggle(let binding):
            return binding.wrappedValue ? "On" : "Off"
        case .select(let options, let selection):
            return options.first { $0.id == selection.wrappedValue }?.title
        case .slider(_, _, let value):
            return String(format: "%.0f", value.wrappedValue)
        case .text(let binding):
            return binding.wrappedValue.isEmpty ? nil : binding.wrappedValue
        case .shortcut(let binding):
            return binding.wrappedValue
        case .secure, .action, .custom:
            return nil
        @unknown default:
            return nil
        }
    }
}
