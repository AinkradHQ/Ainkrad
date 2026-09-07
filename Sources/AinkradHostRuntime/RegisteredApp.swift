import SwiftUI
import AinkradAppKit
import AinkradAppKitContract
import protocol AinkradAppKit.AinkradApp

/// Where a registered app comes from.
public enum AppSource: Equatable {
    case builtIn
    case plugin(url: URL, apiVersion: Int)
}

/// The host-side value the registry holds — the single representation both
/// compiled-in `BuiltInApp`s and dynamically-loaded `AinkradApp` bundles map
/// into. View factories are closures so the concrete app type never leaks.
public struct RegisteredApp: Identifiable {
    public let id: String
    public let displayName: String
    public let icon: String
    /// Short App Store description for built-ins (which have no catalog entry).
    /// Empty for plugins — their description comes from the catalog. Defaulted
    /// so existing construction sites are unaffected.
    public var summary: String = ""
    public let isEnabledByDefault: Bool
    public let source: AppSource
    public let makeRootView: @MainActor () -> AnyView
    public let makeSettingsView: @MainActor () -> AnyView
    public let chromeFill: @MainActor () -> Color?
    /// The app's published settings descriptor, or `nil` if it hasn't adopted
    /// the catalog contract yet (`AinkradApp.settingsCatalog(host:)` defaults
    /// to `nil`). Defaulted here too so no existing construction site breaks.
    public var settingsCatalog: (@MainActor () -> SettingsPage?) = { nil }
    /// How the app's window should be presented (Slice 3): tiled into the
    /// workspace layout (`.pane`, the default) or summoned as a floating
    /// host overlay (`.overlay`) that auto-dismisses when any app opens.
    public var presentation: PluginPresentation = .pane
    /// Releases everything this instance owns. Non-nil only for a plugin whose
    /// app type opts into `AinkradAppTeardown` — see `RegisteredApp.plugin`.
    ///
    /// Defaulted to `nil` so every existing construction site (all the built-in
    /// apps) is unaffected: teardown is opt-in at both ends.
    public var teardown: (@MainActor () -> Void)? = nil
    /// Builds this app's MCP server, or `nil` when the app does not conform to
    /// `AinkradAppMCP`. Defaulted so every existing construction site is
    /// unaffected — capability is opt-in at both ends, exactly like `teardown`.
    /// The host calls this at most once per app and caches the result, so the
    /// server can hold the app's live state.
    public var mcpServerFactory: (@MainActor () -> MCPAppServer)? = nil
    /// Builds this app's Signal observer, or `nil` when the app does not
    /// conform to `AinkradAppSignalObserving`. Opt-in at both ends, like
    /// `teardown` and `mcpServerFactory`.
    ///
    /// Called only when the user has APPROVED the app's declared
    /// subscriptions. An app that declared nothing, or was refused, never has
    /// this invoked — so a refusal costs the app nothing it was already doing,
    /// and a declaration alone cannot cause an observer to be constructed.
    public var signalObserverFactory: (@MainActor () -> any PluginSignalObserver)? = nil
    /// The raw `AinkradSignalSubscriptions` strings from the bundle's
    /// Info.plist, unparsed.
    ///
    /// Carried as written so the host can report the ones it had to DROP.
    /// Parsing here and keeping only the survivors would make a developer's
    /// typo into a subscription that simply never fires, with nothing anywhere
    /// to say why.
    public var declaredSignalSubscriptions: [String] = []

    public init(id: String, displayName: String, icon: String, summary: String = "",
                isEnabledByDefault: Bool, source: AppSource,
                makeRootView: @escaping @MainActor () -> AnyView,
                makeSettingsView: @escaping @MainActor () -> AnyView,
                chromeFill: @escaping @MainActor () -> Color?,
                presentation: PluginPresentation = .pane) {
        self.id = id
        self.displayName = displayName
        self.icon = icon
        self.summary = summary
        self.isEnabledByDefault = isEnabledByDefault
        self.source = source
        self.makeRootView = makeRootView
        self.makeSettingsView = makeSettingsView
        self.chromeFill = chromeFill
        self.presentation = presentation
    }
}

/// A bundle the loader skipped, surfaced for the later App Store UI.
public struct PluginLoadFailure: Equatable {
    public let url: URL
    public let reason: String
    public init(url: URL, reason: String) {
        self.url = url
        self.reason = reason
    }
}

extension RegisteredApp {
    /// Adapts a compiled-in app that conforms to the SDK `AinkradApp` contract,
    /// binding it to its scoped host services. `source == .builtIn`, so the
    /// registry gives it priority over any same-id plugin.
    @MainActor
    public static func builtIn(
        _ app: any AinkradApp.Type,
        isEnabledByDefault: Bool = true,
        summary: String = "",
        host: HostServices,
        chromeFillOverride: (@MainActor () -> Color?)? = nil
    ) -> RegisteredApp {
        var registered = RegisteredApp(
            id: app.id,
            displayName: app.displayName,
            icon: app.icon,
            summary: summary,
            isEnabledByDefault: isEnabledByDefault,
            source: .builtIn,
            makeRootView: { app.makeRootView(host: host) },
            makeSettingsView: { app.makeSettingsView(host: host) },
            // A built-in whose fill depends on host-side state the SDK
            // `chromeFill(host:)` can't see (e.g. the Sage's appearance
            // store) supplies it here; otherwise fall back to the SDK path.
            chromeFill: chromeFillOverride ?? { app.chromeFill(host: host) },
            presentation: .pane
        )
        registered.settingsCatalog = { app.settingsCatalog(host: host) }
        // Discovered by CAST, never a protocol requirement — see PluginLoader
        // for why (an added requirement would break already-compiled bundles).
        if let mcpCapable = app as? AinkradAppMCP.Type {
            registered.mcpServerFactory = { mcpCapable.makeMCPServer(host: host) }
        }
        if let observing = app as? AinkradAppSignalObserving.Type {
            registered.signalObserverFactory = { observing.makeSignalObserver(host: host) }
        }
        return registered
    }
}
