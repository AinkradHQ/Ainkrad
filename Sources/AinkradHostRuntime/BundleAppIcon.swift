/// What to do about the icon stamped on the `.app` bundle itself.
///
/// `NSApplication.applicationIconImage` only dresses the Dock tile of the
/// RUNNING process — quit Ainkrad and the Finder/Dock fall back to the
/// bundle's shipped `AppIcon.icns`, which is why a chosen icon looked like it
/// reverted on quit. Making the choice stick means stamping a custom icon onto
/// the bundle, and the only macOS API for that (`NSWorkspace.setIcon`) writes
/// Finder metadata into it.
///
/// That metadata costs a `codesign --verify --strict` failure (`resource fork,
/// Finder information, or similar detritus not allowed`), so it is written as
/// rarely as possible: only when the resolved icon actually changes, and never
/// when the shipped icon is already the right one — hence `clear`, which puts
/// an already-stamped bundle back to a strict-clean state.
public enum BundleAppIconDecision: Equatable {
    /// The bundle already shows the right icon — touch nothing.
    case none
    /// Stamp this `.icns` resource base-name onto the bundle.
    case write(String)
    /// Remove the stamp so the bundle's own shipped icon shows through.
    case clear
}

public enum BundleAppIcon {
    /// - Parameters:
    ///   - resolved: the `.icns` base-name the user's settings resolve to.
    ///   - lastWritten: the name last stamped by this app, or `nil` if the
    ///     bundle carries no stamp.
    ///   - matchesShippedIcon: whether `resolved` is byte-for-byte the icon the
    ///     bundle already ships as `AppIcon.icns`.
    public static func decide(resolved: String,
                              lastWritten: String?,
                              matchesShippedIcon: Bool) -> BundleAppIconDecision {
        if matchesShippedIcon {
            // The shipped icon is already correct, so a stamp would only add
            // signature detritus for no visible change. Remove one if present.
            return lastWritten == nil ? .none : .clear
        }
        return resolved == lastWritten ? .none : .write(resolved)
    }
}
