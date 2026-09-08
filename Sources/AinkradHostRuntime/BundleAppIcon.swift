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
///
/// Open questions this trade-off has NOT measured (both are keyed to code
/// identity, same as the `codesign --verify --strict` failure above):
/// whether `spctl --assess` still passes on a stamped bundle, and whether TCC
/// grants (Screen Recording, Accessibility, Automation) survive a relaunch
/// after stamping. Treat both as unverified, not as "fine because codesign
/// --verify was checked" — that check does not cover them.
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
    ///   - lastWrittenBundleVersion: the bundle version (`CFBundleVersion`) that
    ///     was current when `lastWritten` was recorded, or `nil` if unknown.
    ///     The stamp itself lives inside the `.app` bundle and does not survive
    ///     an app update/reinstall, while `UserDefaults` does — so bookkeeping
    ///     from a previous bundle no longer describes reality and must be
    ///     treated as if no stamp existed.
    ///   - currentBundleVersion: the running app's `CFBundleVersion`.
    ///   - matchesShippedIcon: whether `resolved` is byte-for-byte the icon the
    ///     bundle already ships as `AppIcon.icns`.
    public static func decide(resolved: String,
                              lastWritten: String?,
                              lastWrittenBundleVersion: String? = nil,
                              currentBundleVersion: String? = nil,
                              matchesShippedIcon: Bool) -> BundleAppIconDecision {
        // Staleness is only detectable when both versions are actually known;
        // callers that don't pass version info (or tests exercising the
        // version-agnostic behavior) get the old, un-versioned semantics.
        let staleBookkeeping = lastWritten != nil
            && lastWrittenBundleVersion != nil
            && currentBundleVersion != nil
            && lastWrittenBundleVersion != currentBundleVersion
        let effectiveLastWritten = staleBookkeeping ? nil : lastWritten

        if matchesShippedIcon {
            // The shipped icon is already correct, so a stamp would only add
            // signature detritus for no visible change. Remove one if present
            // (but only if it's actually on THIS bundle — nothing to clear on
            // a bundle we never wrote).
            return (effectiveLastWritten == nil || staleBookkeeping) ? .none : .clear
        }
        return resolved == effectiveLastWritten ? .none : .write(resolved)
    }
}
