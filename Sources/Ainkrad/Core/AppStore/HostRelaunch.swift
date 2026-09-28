import AppKit

/// Quits Ainkrad and opens it again — the only way a replaced plugin bundle
/// takes effect, because dyld never unloads the old one.
///
/// A detached shell waits for THIS process to exit before `open`, so the new
/// instance never races the old one for the single-instance slot.
enum HostRelaunch {
    @MainActor
    static func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let app = Bundle.main.bundleURL.path
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open \"$0\"", app]
        do { try task.run() } catch { return }   // no relaunch → don't quit either
        NSApp.terminate(nil)
    }
}
