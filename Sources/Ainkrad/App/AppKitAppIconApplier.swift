import AppKit
import AinkradHostRuntime

/// Real `AppIconApplying`: sets the running app's Dock icon to the composed
/// `.icns` resolved from the user's color + appearance settings and (for Auto)
/// the current theme, under the current system appearance. Re-applies when the
/// system Light/Dark appearance changes (relevant when Appearance = System).
///
/// It also stamps the choice onto the `.app` bundle so it survives quitting —
/// see `BundleAppIcon` for why that is a separate, deliberately rare write.
@MainActor
final class AppKitAppIconApplier: NSObject, AppIconApplying {
    /// UserDefaults key holding the `.icns` base-name last stamped onto the
    /// bundle. App-local bookkeeping, not a user preference, so it is kept out
    /// of `GlobalSettings`. Absent = the bundle carries no stamp of ours.
    private static let stampedIconKey = "appIcon.stampedBundleResource"

    private var choice: AppIconChoice = .auto
    private var appearance: AppIconAppearance = .system
    private var theme: Theme = .neonBlue
    private var observation: NSKeyValueObservation?

    override init() {
        super.init()
        observation = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.reapply() }
        }
    }

    func apply(choice: AppIconChoice, appearance: AppIconAppearance, theme: Theme) {
        self.choice = choice
        self.appearance = appearance
        self.theme = theme
        reapply()
    }

    private func reapply() {
        let systemDark = NSApplication.shared.effectiveAppearance
            .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let name = AppIconResolver.resourceName(for: choice, theme: theme,
                                                appearance: appearance, systemDark: systemDark)
        guard let url = Bundle.main.url(forResource: name, withExtension: "icns"),
              let image = NSImage(contentsOf: url) else { return }
        NSApplication.shared.applicationIconImage = image
        stampBundleIcon(resource: name, iconURL: url)
    }

    // MARK: - Persisting the icon past quit

    /// Makes the Finder/Dock show the chosen icon while Ainkrad is not
    /// running. Best-effort by design: a bundle we cannot write (installed by
    /// another user, read-only volume, a translocated copy) just keeps its
    /// shipped icon, and the running app's Dock tile is already correct either
    /// way — so this never surfaces an error at the user.
    private func stampBundleIcon(resource: String, iconURL: URL) {
        let defaults = UserDefaults.standard
        let bundleURL = Bundle.main.bundleURL
        let decision = BundleAppIcon.decide(
            resolved: resource,
            lastWritten: defaults.string(forKey: Self.stampedIconKey),
            matchesShippedIcon: shippedIconMatches(iconURL))

        switch decision {
        case .none:
            return
        case .clear:
            guard NSWorkspace.shared.setIcon(nil, forFile: bundleURL.path, options: []) else {
                Log.app.error("Could not clear the bundle icon stamp at \(bundleURL.path, privacy: .public)")
                return
            }
            defaults.removeObject(forKey: Self.stampedIconKey)
        case .write(let name):
            guard let image = NSImage(contentsOf: iconURL),
                  NSWorkspace.shared.setIcon(image, forFile: bundleURL.path, options: []) else {
                Log.app.error("Could not stamp icon \(name, privacy: .public) onto \(bundleURL.path, privacy: .public)")
                return
            }
            defaults.set(name, forKey: Self.stampedIconKey)
        }
    }

    /// Whether the bundle's shipped `AppIcon.icns` already IS this icon, in
    /// which case stamping would add signature detritus for no visible change.
    private func shippedIconMatches(_ iconURL: URL) -> Bool {
        guard let shipped = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let a = try? Data(contentsOf: shipped),
              let b = try? Data(contentsOf: iconURL) else { return false }
        return a == b
    }
}
