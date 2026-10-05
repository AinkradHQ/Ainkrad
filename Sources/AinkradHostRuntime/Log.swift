import AinkradAppKitContract
import os

/// The host's `os.Logger` categories — the one `Log` for both the app target
/// and this module (the app imports it from here). Every logger comes from
/// `AinkradLog.logger(app:area:)` (S-LOG-1), so the host shares the subsystem
/// every plugin logs under and one Console.app filter covers the whole install.
/// Categories read `host.<area>`. See AIN-45.
public enum Log {
    public static let app = AinkradLog.logger(app: "host", area: "app")
    public static let registry = AinkradLog.logger(app: "host", area: "registry")
    public static let settings = AinkradLog.logger(app: "host", area: "settings")
    public static let terminal = AinkradLog.logger(app: "host", area: "terminal")
    public static let persistence = AinkradLog.logger(app: "host", area: "persistence")
    public static let appStore = AinkradLog.logger(app: "host", area: "appStore")
    public static let mcp = AinkradLog.logger(app: "host", area: "mcp")
    public static let lsp = AinkradLog.logger(app: "host", area: "lsp")
    /// Crash sentinel and signpost plumbing — see `CrashSentinel`, AIN-45.
    public static let diagnostics = AinkradLog.logger(app: "host", area: "diagnostics")
}
