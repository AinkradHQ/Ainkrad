import os

/// The four intervals Plan A measures. Signposts are near-free when Instruments
/// is not recording, so these stay compiled into Release — a performance
/// problem that only reproduces on a user's machine is not reproducible at all
/// if the instrumentation is Debug-only.
public enum AinkradSignposts {
    private static let subsystem = "com.ainkrad.app"

    public static let launch = OSSignposter(subsystem: subsystem, category: "launch")
    public static let persistence = OSSignposter(subsystem: subsystem, category: "persistence")
    public static let agent = OSSignposter(subsystem: subsystem, category: "agent")

    public static func begin(_ signposter: OSSignposter, _ name: StaticString) -> OSSignpostIntervalState {
        signposter.beginInterval(name, id: signposter.makeSignpostID())
    }

    public static func end(_ signposter: OSSignposter, _ name: StaticString,
                           _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }
}
