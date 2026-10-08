import AinkradAppKitUI
import Foundation

/// Loads theme and colour-scheme files from the main bundle and from user
/// folders, and composes a theme variant with a colour scheme into one skin.
///
/// Two kinds of file, told apart by extension:
/// - `*.theme` — a base skin, or (with `host.language`) a design-language variant.
/// - `*.scheme` — a colour scheme (`palette`, `terminal`, `syntax`, sky/icon `host`).
///
/// A user file never replaces a bundled id; among user roots the first root wins.
/// Every problem is kept in `issues` and the file is skipped — loading never traps.
/// `ThemeManager` owns the one instance the app uses.
// Safe because every read and write of `snapshot` and `composed` goes through `lock`.
public final class ThemeCatalog: @unchecked Sendable {
    struct LoadedTheme: Sendable {
        let themeFile: AinkradThemeFile
        let hostSection: HostSkinSection?
    }

    private struct Snapshot {
        var loadedThemes: [String: LoadedTheme] = [:]
        var schemes: [String: ThemeColorScheme] = [:]
        var issues: [ThemeCatalogIssue] = []
    }

    /// The theme-file format this host reads. A store entry with a higher `format` is hidden.
    public static let supportedFormat = 1

    let bundle: Bundle
    let userRoots: [URL]
    private let lock = NSLock()
    private var snapshot = Snapshot()
    private var composed: [String: AinkradThemeFile] = [:]

    /// - Parameter userRoots: folders scanned recursively for `*.theme` and
    ///   `*.scheme`, highest priority first.
    public init(bundle: Bundle = .main, userRoots: [URL] = []) {
        self.bundle = bundle
        self.userRoots = userRoots
        self.snapshot = Self.load(bundle: bundle, userRoots: userRoots)
    }

    /// Re-reads every file and drops composed results.
    @MainActor
    func reload() {
        let fresh = Self.load(bundle: bundle, userRoots: userRoots)
        lock.withLock {
            snapshot = fresh
            composed = [:]
        }
    }

    var loadedThemes: [String: LoadedTheme] { lock.withLock { snapshot.loadedThemes } }
    var issues: [ThemeCatalogIssue] { lock.withLock { snapshot.issues } }

    // MARK: - Languages, variants and schemes

    /// One entry per design language, sorted by name.
    var languages: [LanguageSection] {
        var byID: [String: LanguageSection] = [:]
        for loaded in loadedThemes.values {
            guard let language = loaded.hostSection?.language else { continue }
            byID[language.id] = byID[language.id] ?? language
        }
        return byID.values.sorted { $0.name < $1.name }
    }

    /// The variant files (file id → theme) of one design language.
    func variants(of languageID: String) -> [String: LoadedTheme] {
        loadedThemes.filter { $0.value.hostSection?.language?.id == languageID }
    }

    /// Colour schemes for one appearance, sorted by name.
    public func schemes(for appearance: ThemeAppearance) -> [ThemeColorScheme] {
        lock.withLock { snapshot.schemes.values }
            .filter { $0.appearance == appearance }
            .sorted { $0.name < $1.name }
    }

    /// The skin of `themeVariant` coloured by `scheme`, or nil when either id is
    /// unknown or the pair does not compose. The composed skin's id is the scheme id.
    @MainActor
    public func compose(themeVariant variantID: String, scheme schemeID: String) -> AinkradThemeFile? {
        let key = "\(variantID)|\(schemeID)"
        let (cached, variant, scheme) = lock.withLock {
            (composed[key], snapshot.loadedThemes[variantID], snapshot.schemes[schemeID])
        }
        if let cached { return cached }
        guard let variant, variant.hostSection?.language != nil, let scheme else { return nil }
        guard let file = try? Self.compose(variantID: variantID, variant: variant, scheme: scheme) else { return nil }
        lock.withLock { composed[key] = file }
        return file
    }

    // MARK: - Loading

    private static let maxFileBytes = 256 * 1024

    private static func load(bundle: Bundle, userRoots: [URL]) -> Snapshot {
        var snapshot = Snapshot()
        let bundleFiles =
            Set(
                (bundle.urls(forResourcesWithExtension: "theme", subdirectory: "Themes") ?? [])
                    + (bundle.urls(forResourcesWithExtension: "theme", subdirectory: nil) ?? [])
                    + (bundle.urls(forResourcesWithExtension: "scheme", subdirectory: "Themes/ColorSchemes") ?? [])
            ).sorted { $0.path < $1.path }
        let sources: [(name: String, files: [URL])] =
            [("bundle", bundleFiles)] + userRoots.map { ($0.path, userFiles(under: $0)) }

        // Read and claim ids, bundle first. Themes and schemes are separate id
        // spaces: scheme `neonBlue` and base skin `neonBlue` coexist.
        var themeData: [Data] = []
        var schemeDicts: [[String: Any]] = []
        var claimed: [String: String] = [:]  // "<ext>:<id>" → source
        for source in sources {
            for url in source.files {
                let fileName = url.lastPathComponent
                guard let data = try? Data(contentsOf: url) else {
                    snapshot.issues.append(ThemeCatalogIssue(subject: fileName, message: "unreadable"))
                    continue
                }
                guard data.count <= maxFileBytes else {
                    snapshot.issues.append(
                        ThemeCatalogIssue(subject: fileName, message: "\(data.count) bytes, over the 256 KB limit"))
                    continue
                }
                guard let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    snapshot.issues.append(ThemeCatalogIssue(subject: fileName, message: "not a JSON object"))
                    continue
                }
                guard let id = dict["id"] as? String else {
                    snapshot.issues.append(ThemeCatalogIssue(subject: fileName, message: "missing id"))
                    continue
                }
                let claim = "\(url.pathExtension):\(id)"
                if let owner = claimed[claim] {
                    snapshot.issues.append(
                        ThemeCatalogIssue(subject: fileName, message: "id \(id) is already provided by \(owner); skipped"))
                    continue
                }
                claimed[claim] = source.name
                if url.pathExtension == "scheme" { schemeDicts.append(dict) } else { themeData.append(data) }
            }
        }

        let result = ainkradLoadThemes(themeData)
        for issue in result.issues {
            var isWarning = false
            if case .unknownValue = issue.error { isWarning = true }
            snapshot.issues.append(
                ThemeCatalogIssue(
                    subject: "theme \(issue.fileId ?? "?")", message: issue.error.description, isWarning: isWarning))
        }
        for (id, file) in result.themes {
            var section: HostSkinSection?
            if let hostData = file.host {
                do {
                    section = try JSONDecoder().decode(HostSkinSection.self, from: hostData)
                } catch {
                    snapshot.issues.append(
                        ThemeCatalogIssue(subject: "theme \(id)", message: "host section: \(error.localizedDescription)"))
                }
            }
            snapshot.loadedThemes[id] = LoadedTheme(themeFile: file, hostSection: section)
            for problem in HomeLanguage.resolve(section?.language).problems {
                snapshot.issues.append(ThemeCatalogIssue(subject: "theme \(id)", message: problem, isWarning: true))
            }
        }

        // Every scheme is test-composed once against a variant of its appearance
        // (Neon's when present); one that fails stays out of the picker.
        for dict in schemeDicts {
            let scheme: ThemeColorScheme
            switch ThemeColorScheme.parse(dict) {
            case .success(let parsed): scheme = parsed
            case .failure(let issue):
                snapshot.issues.append(issue)
                continue
            }
            if let (variantID, variant) = probeVariant(for: scheme.appearance, in: snapshot.loadedThemes) {
                do {
                    _ = try compose(variantID: variantID, variant: variant, scheme: scheme)
                } catch {
                    snapshot.issues.append(
                        ThemeCatalogIssue(subject: "scheme \(scheme.id)", message: "does not compose: \(error)"))
                    continue
                }
            }
            snapshot.schemes[scheme.id] = scheme
        }
        for issue in snapshot.issues {
            Log.settings.error("Theme catalog load issue: \(issue.description, privacy: .public)")
        }
        return snapshot
    }

    /// Regular `*.theme`/`*.scheme` files under `root`, recursively, sorted.
    /// Hidden files and symlinks are skipped.
    private static func userFiles(under root: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isRegularFileKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where ["theme", "scheme"].contains(url.pathExtension) {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isSymbolicLink != true, values?.isRegularFile == true else { continue }
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func probeVariant(
        for appearance: ThemeAppearance, in themes: [String: LoadedTheme]
    ) -> (String, LoadedTheme)? {
        let candidates = themes.filter { $0.value.hostSection?.language?.appearance == appearance }
            .sorted { $0.key < $1.key }
        return candidates.first { $0.value.hostSection?.language?.id == "neon" } ?? candidates.first
    }

    /// Scheme on top of variant: `base` = the variant, `id` = the scheme, and the
    /// `host` blocks merged by hand (the decoder replaces `host` rather than merging).
    private static func compose(
        variantID: String, variant: LoadedTheme, scheme: ThemeColorScheme
    ) throws -> AinkradThemeFile {
        guard var dict = try JSONSerialization.jsonObject(with: scheme.raw) as? [String: Any] else {
            throw ThemeCatalogIssue(subject: "scheme \(scheme.id)", message: "not a JSON object")
        }
        dict.removeValue(forKey: "appearance")
        dict["base"] = variantID
        dict["id"] = scheme.id
        var host =
            variant.themeFile.host.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let schemeHost = dict["host"] as? [String: Any] ?? [:]
        for key in ["skyProfile", "iconColorFamily"] {
            if let value = schemeHost[key] { host[key] = value }
        }
        if host.isEmpty { dict.removeValue(forKey: "host") } else { dict["host"] = host }
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        return try AinkradThemeFile(decoding: data, bases: [variantID: variant.themeFile])
    }
}

extension ThemeCatalogIssue: Error {}
