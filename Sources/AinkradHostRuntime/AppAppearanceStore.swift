import Foundation
import Observation
import AinkradAppKit

/// One app's surface appearance. `surfaceOpacity` is honored only for
/// host-background apps (the Sage); every app honors `blurEnabled`.
public struct AppAppearanceEntry: Codable, Equatable {
    public var surfaceOpacity: Double = 1.0
    public var blurEnabled: Bool = false
    /// User override of the app's presentation, as `PluginPresentation.rawValue`.
    /// `nil` = use the bundle's declared default. Applies on next open.
    public var presentationOverride: String? = nil
    /// User override of the mode the app OPENS in, as `PluginMode.rawValue`
    /// (generation 11). `nil` = use the bundle's `AinkradMode`. Applies to
    /// panes opened after it; it is not the mode an open pane is showing.
    public var modeOverride: String? = nil
    /// Per-app font overrides, as `UIFontFamily` / `UIFontScale` raw values.
    /// `nil` = inherit the global Appearance setting.
    public var fontFamily: String? = nil
    public var fontScale: String? = nil

    public init(surfaceOpacity: Double = 1.0, blurEnabled: Bool = false,
                presentationOverride: String? = nil, fontFamily: String? = nil, fontScale: String? = nil,
                modeOverride: String? = nil) {
        self.surfaceOpacity = surfaceOpacity
        self.blurEnabled = blurEnabled
        self.presentationOverride = presentationOverride
        self.fontFamily = fontFamily
        self.fontScale = fontScale
        self.modeOverride = modeOverride
    }
}

/// Per-app surface appearance, keyed by `appID` (the Sage is one surface
/// among many now — Terminal, Git Mage, and any plugin have their own entry).
public struct AppAppearanceDocument: PersistableDocument {
    public static let documentID = "app-appearance"
    public static let currentSchemaVersion = 3

    /// v1 → v2: the 2026-08-02 app rename. Entries keyed by the retired ids
    /// (`assistant`, `canvas`, `files`, `terminal`) move to their new ids so a
    /// user's opacity, blur, presentation override and per-app fonts survive.
    public static let migrators: [DocumentMigrator] = [
        DocumentMigrator(from: 1) { payload in
            guard case .object(var root) = payload,
                  case .object(let entries)? = root["entries"] else { return payload }
            root["entries"] = .object(AppIDRenames.rekeyed(entries))
            return .object(root)
        },
        // v2 → v3: `modeOverride` (generation 11). The payload needs no
        // transformation — it is a new optional field, so a v2 entry decodes
        // with it nil, which already means "no override, use the bundle
        // default".
        //
        // It still has to EXIST. `FileDocumentStore` walks the chain one step
        // at a time and fails the whole load when a step has no migrator, so
        // bumping the version without this identity step does not quietly keep
        // working — it drops every user's per-app opacity, blur, presentation
        // override and fonts on first launch. `AppIDMigrationTests` catches it.
        DocumentMigrator(from: 2) { $0 },
    ]

    public var entries: [String: AppAppearanceEntry] = [:]

    public init(entries: [String: AppAppearanceEntry] = [:]) {
        self.entries = entries
    }
}

/// The Slice-2c Assistant-only document (named for the app Sage used to be).
/// Retained ONLY so a first load can migrate that opacity/blur into the
/// `"sage"` entry of the per-app store. Not `private` so the migration test can seed it.
public struct LegacyAssistantAppearanceDocument: PersistableDocument {
    public static let documentID = "assistant-appearance"
    public var surfaceOpacity: Double
    public var blurEnabled: Bool

    public init(surfaceOpacity: Double = 1.0, blurEnabled: Bool = false) {
        self.surfaceOpacity = surfaceOpacity
        self.blurEnabled = blurEnabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        surfaceOpacity = try c.decodeIfPresent(Double.self, forKey: .surfaceOpacity) ?? 1.0
        blurEnabled = try c.decodeIfPresent(Bool.self, forKey: .blurEnabled) ?? false
    }
}

/// Observable per-app appearance store. Same load/mutate/save pattern as the
/// other settings stores; opacity setter clamps to `0…1`.
@MainActor
@Observable
public final class AppAppearanceStore {
    private var document: AppAppearanceDocument
    private let persistence: PersistenceStore

    public init(persistence: PersistenceStore) {
        self.persistence = persistence
        var doc = persistence.load(AppAppearanceDocument.self) ?? AppAppearanceDocument()
        // One-time migration: fold the Slice-2c Assistant-only store into the
        // per-app map so the user's opacity/blur carries over. Targets "sage",
        // NOT "assistant": the schema-v2 migrator above has already rekeyed the
        // map, so folding into the retired id would write an entry nothing reads.
        if doc.entries["sage"] == nil,
           let legacy = persistence.load(LegacyAssistantAppearanceDocument.self) {
            doc.entries["sage"] = AppAppearanceEntry(
                surfaceOpacity: legacy.surfaceOpacity, blurEnabled: legacy.blurEnabled)
            persistence.save(doc)
        }
        self.document = doc
    }

    public func blurEnabled(_ appID: String) -> Bool { document.entries[appID]?.blurEnabled ?? false }
    public func surfaceOpacity(_ appID: String) -> Double { document.entries[appID]?.surfaceOpacity ?? 1.0 }

    public func setBlurEnabled(_ appID: String, _ isOn: Bool) {
        var entry = document.entries[appID] ?? AppAppearanceEntry()
        entry.blurEnabled = isOn
        document.entries[appID] = entry
        persistence.save(document)
    }

    public func setSurfaceOpacity(_ appID: String, _ value: Double) {
        var entry = document.entries[appID] ?? AppAppearanceEntry()
        entry.surfaceOpacity = min(max(value, 0), 1)
        document.entries[appID] = entry
        persistence.save(document)
    }

    public func presentationOverride(_ appID: String) -> PluginPresentation? {
        document.entries[appID]?.presentationOverride.flatMap(PluginPresentation.init(rawValue:))
    }

    public func setPresentationOverride(_ appID: String, _ value: PluginPresentation?) {
        var entry = document.entries[appID] ?? AppAppearanceEntry()
        entry.presentationOverride = value?.rawValue
        document.entries[appID] = entry
        persistence.save(document)
    }

    public func modeOverride(_ appID: String) -> PluginMode? {
        document.entries[appID]?.modeOverride.flatMap(PluginMode.init(rawValue:))
    }

    public func setModeOverride(_ appID: String, _ value: PluginMode?) {
        var entry = document.entries[appID] ?? AppAppearanceEntry()
        entry.modeOverride = value?.rawValue
        document.entries[appID] = entry
        persistence.save(document)
    }

    /// The mode a NEW pane of `app` opens in: the user's override if set,
    /// otherwise the app's declared `AinkradMode`.
    ///
    /// One resolver so the pane layer and any other opener cannot drift — the
    /// presentation equivalent is still spelled out at each call site, which is
    /// exactly the drift risk worth not repeating.
    public func effectiveMode(for app: RegisteredApp) -> PluginMode {
        guard app.supportsModes else { return .advanced }
        return modeOverride(app.id) ?? app.mode
    }

    public func fontFamily(_ appID: String) -> UIFontFamily? {
        document.entries[appID]?.fontFamily.flatMap(UIFontFamily.init(rawValue:))
    }

    public func setFontFamily(_ appID: String, _ value: UIFontFamily?) {
        var entry = document.entries[appID] ?? AppAppearanceEntry()
        entry.fontFamily = value?.rawValue
        document.entries[appID] = entry
        persistence.save(document)
    }

    public func fontScale(_ appID: String) -> UIFontScale? {
        document.entries[appID]?.fontScale.flatMap(UIFontScale.init(rawValue:))
    }

    public func setFontScale(_ appID: String, _ value: UIFontScale?) {
        var entry = document.entries[appID] ?? AppAppearanceEntry()
        entry.fontScale = value?.rawValue
        document.entries[appID] = entry
        persistence.save(document)
    }
}
