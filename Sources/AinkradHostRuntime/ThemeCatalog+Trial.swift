import Foundation

extension ThemeCatalog {
    /// Trial-loads a store entry's files (flat in `staged`) ahead of this catalog's
    /// own roots and returns every problem with them; empty = safe to install.
    ///
    /// Checks: the files load with zero issues of their own; the identity binding
    /// (a theme's variants carry `host.language.id == entryID` and each scheme is
    /// one a variant names as default; a scheme entry's file has `id == entryID`);
    /// a variant's `base` is a bundled base skin; and every variant composes with
    /// its default scheme or Neon's. Main actor only: skin decode overflows a worker stack.
    @MainActor
    public func trialProblems(entryID: String, isTheme: Bool, staged: URL) -> [String] {
        var themeFiles: [String: [String: Any]] = [:]  // id → top-level object
        var schemeIDs: [String] = []
        var subjects: Set<String> = []
        let urls = (try? FileManager.default.contentsOfDirectory(at: staged, includingPropertiesForKeys: nil)) ?? []
        for url in urls {
            subjects.insert(url.lastPathComponent)
            guard let data = try? Data(contentsOf: url),
                let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                let id = dict["id"] as? String
            else { continue }
            if url.pathExtension == "scheme" {
                schemeIDs.append(id)
                subjects.insert("scheme \(id)")
            } else {
                themeFiles[id] = dict
                subjects.insert("theme \(id)")
            }
        }

        let trial = ThemeCatalog(bundle: bundle, userRoots: [staged] + userRoots)
        // An installed older copy losing its ids to the staged files is the update itself, not a problem.
        let displaced = "already provided by \(staged.path); skipped"
        let issues = trial.issues.filter { subjects.contains($0.subject) && !$0.message.hasSuffix(displaced) }
        if !issues.isEmpty { return issues.map(\.description) }

        var problems: [String] = []
        let loadedSchemes = Set(ThemeAppearance.allCases.flatMap { trial.schemes(for: $0) }.map(\.id))
        guard isTheme else {
            if schemeIDs != [entryID] {
                problems.append("scheme \(schemeIDs.first ?? "?"): id must be \(entryID)")
            } else if !loadedSchemes.contains(entryID) { problems.append("scheme \(entryID): did not load") }
            return problems
        }

        let bundledBases = Set(
            ThemeCatalog(bundle: bundle).loadedThemes.filter { $0.value.hostSection?.language == nil }.keys)
        var defaultSchemes: [String: String] = [:]  // scheme id → variant naming it
        for (id, dict) in themeFiles.sorted(by: { $0.key < $1.key }) {
            guard let language = trial.loadedThemes[id]?.hostSection?.language, language.id == entryID else {
                problems.append("theme \(id): host.language.id must be \(entryID)")
                continue
            }
            if let base = dict["base"] as? String, !bundledBases.contains(base) {
                problems.append("theme \(id): unknownBase \(base) (a store theme may base only on a bundled base skin)")
            }
            defaultSchemes[language.defaultColorScheme] = id
            if trial.compose(themeVariant: id, scheme: language.defaultColorScheme) == nil,
                trial.compose(themeVariant: id, scheme: LanguageSection().defaultColorScheme) == nil
            {
                problems.append("theme \(id): composes with neither \(language.defaultColorScheme) nor Neon")
            }
        }
        for id in schemeIDs.sorted() {
            if let variant = defaultSchemes[id] {
                if trial.compose(themeVariant: variant, scheme: id) == nil {
                    problems.append("scheme \(id): does not compose with \(variant)")
                }
            } else {
                problems.append("scheme \(id): not a default colour scheme of \(entryID)")
            }
        }
        return problems
    }
}
