import Foundation

/// One entry in the Hoard sidebar.
struct SidebarRoot: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    /// SF Symbol name — tinted from the theme at render time, never here.
    var icon: String
    var url: URL
}

/// A titled group of sidebar rows. Sections exist so favourites and
/// repositories are visibly distinct from the fixed places — a flat list of
/// twenty entries reads as noise.
struct SidebarSection: Identifiable, Equatable, Sendable {
    var id: String
    /// `nil` for the standard places, which need no heading.
    var title: String?
    var roots: [SidebarRoot]
    /// Whether rows here can be unpinned.
    var isRemovable: Bool = false
}

/// The whole sidebar, in order: places, then favourites, then repositories.
///
/// Pure, so the composition is testable without a filesystem: empty groups are
/// dropped rather than rendered as bare headings, and a pinned folder that is
/// already a standard place is not shown twice.
func sidebarSections(
    home: URL, pinned: [URL] = [],
    repositories: [URL] = []
) -> [SidebarSection] {
    let places = standardRoots(home: home)
    let placePaths = Set(places.map(\.url.path))

    var sections = [SidebarSection(id: "places", title: nil, roots: places)]

    let favourites =
        pinned
        .filter { !placePaths.contains($0.path) }
        .map {
            SidebarRoot(
                id: "pin-\($0.path)", name: $0.lastPathComponent,
                icon: "star.fill", url: $0)
        }
    if !favourites.isEmpty {
        sections.append(
            SidebarSection(
                id: "favourites", title: "Favourites",
                roots: favourites, isRemovable: true))
    }

    // Repositories the user has actually visited — never a background scan of
    // the home folder, which would be a recursive walk of everything they own.
    let repos =
        repositories
        .filter { !placePaths.contains($0.path) }
        .map {
            SidebarRoot(
                id: "repo-\($0.path)", name: $0.lastPathComponent,
                icon: "shippingbox", url: $0)
        }
    if !repos.isEmpty {
        sections.append(SidebarSection(id: "repositories", title: "Repositories", roots: repos))
    }
    return sections
}

/// The built-in roots, home first. Takes `home` as a parameter rather than
/// reading `FileManager` so it is pure and testable.
///
/// These are shown unconditionally, without checking existence: a missing
/// Desktop (possible with iCloud Desktop disabled) should render as an entry
/// whose listing fails visibly, not silently vanish from the sidebar.
func standardRoots(home: URL) -> [SidebarRoot] {
    [
        SidebarRoot(id: "home", name: "Home", icon: "house", url: home),
        SidebarRoot(
            id: "desktop", name: "Desktop", icon: "menubar.dock.rectangle",
            url: home.appendingPathComponent("Desktop")),
        SidebarRoot(
            id: "documents", name: "Documents", icon: "doc",
            url: home.appendingPathComponent("Documents")),
        SidebarRoot(
            id: "downloads", name: "Downloads", icon: "arrow.down.circle",
            url: home.appendingPathComponent("Downloads")),
        SidebarRoot(
            id: "applications", name: "Applications", icon: "square.grid.2x2",
            url: URL(fileURLWithPath: "/Applications")),
    ]
}
