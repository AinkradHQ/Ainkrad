import AinkradHostRuntime
import Foundation
import Observation

/// Hoard-specific display settings that have no home in `AppAppearanceStore`
/// (which owns opacity, blur and font overrides for every app).
struct HoardSettingsDocument: PersistableDocument {
    static let documentID = "files-settings"

    var iconSize: Double = 13
    var showMetadataColumns: Bool = true
    var showPreview: Bool = false
    var useGrid: Bool = false
    var vimKeys: Bool = false

    init(
        iconSize: Double = 13, showMetadataColumns: Bool = true, showPreview: Bool = false,
        useGrid: Bool = false, vimKeys: Bool = false
    ) {
        self.iconSize = iconSize
        self.showMetadataColumns = showMetadataColumns
        self.showPreview = showPreview
        self.useGrid = useGrid
        self.vimKeys = vimKeys
    }
}

@MainActor
@Observable
final class HoardSettingsStore {
    /// DIRECTLY STORED, deliberately.
    ///
    /// These were computed properties wrapping a private `document` struct,
    /// and the icon-size slider then had no visible effect: SwiftUI's
    /// observation is reliable for stored properties, and routing reads and
    /// writes through a computed accessor over nested struct state is exactly
    /// where dependency registration gets missed. Persistence happens in
    /// `didSet`, so the storage stays the source of truth for the view and the
    /// document is only ever a serialization detail.
    var iconSize: Double = 13 {
        didSet {
            // Clamped: a zero-point icon collapses rows to a text sliver, and
            // an oversized one breaks the row rhythm against the sidebar.
            let clamped = min(max(10, iconSize), 22)
            if clamped != iconSize {
                iconSize = clamped
                return  // The re-entrant set below persists.
            }
            persist()
        }
    }

    var showMetadataColumns: Bool = true {
        didSet { persist() }
    }

    /// Preview strip visibility, toggled by ⌘Y. Persisted so the pane comes
    /// back the way you left it.
    var showPreview: Bool = false {
        didSet { persist() }
    }

    /// Grid instead of list — for image-heavy folders.
    var useGrid: Bool = false {
        didSet { persist() }
    }

    /// The opt-in modal `hjkl` layer, DEFAULT OFF.
    ///
    /// vim keys and type-to-select are in direct conflict: with `hjkl` bound,
    /// typing "h" to jump to "Home" moves the cursor left instead. Silently
    /// breaking type-to-select makes the app feel broken rather than powerful,
    /// so this is a choice the user makes, never a default.
    var vimKeys: Bool = false {
        didSet { persist() }
    }

    private let persistence: PersistenceStore

    init(persistence: PersistenceStore) {
        self.persistence = persistence
        let document = persistence.load(HoardSettingsDocument.self) ?? HoardSettingsDocument()
        // Assigned before `persistence` participates in any didSet write-back
        // of values we just read — these are the loaded values, not changes.
        self.iconSize = min(max(10, document.iconSize), 22)
        self.showMetadataColumns = document.showMetadataColumns
        self.showPreview = document.showPreview
        self.useGrid = document.useGrid
        self.vimKeys = document.vimKeys
    }

    private func persist() {
        persistence.save(
            HoardSettingsDocument(
                iconSize: iconSize, showMetadataColumns: showMetadataColumns,
                showPreview: showPreview, useGrid: useGrid, vimKeys: vimKeys))
    }

    /// Row vertical padding derived from icon size, so density scales as one
    /// coherent thing instead of leaving big icons in cramped rows.
    var rowVerticalPadding: CGFloat { CGFloat(iconSize) * 0.38 }
}
