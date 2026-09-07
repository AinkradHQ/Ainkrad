import Foundation
import MetricKit

/// Installs the two diagnostic sources macOS offers a non-sandboxed app:
/// an uncaught-`NSException` handler (synchronous, catches the dying process)
/// and a `MetricKit` subscriber (asynchronous, delivers hangs, CPU/disk
/// exceptions and crash diagnostics from PREVIOUS runs, typically at next launch).
///
/// Neither catches a Swift runtime trap (`fatalError`, force-unwrap of nil,
/// index out of range) — those raise SIGILL/SIGTRAP and are reported by
/// MetricKit's `crashDiagnostics` on the following launch, not in-process.
/// That asymmetry is why Plan F removes the avoidable trap sites rather than
/// trying to catch them.
enum CrashSentinel {
    nonisolated(unsafe) private static var writer: CrashLogWriter?
    nonisolated(unsafe) private static let subscriber = MetricSubscriber()

    static func install(
        writer: CrashLogWriter = CrashLogWriter(directory: CrashLogWriter.defaultDirectory)
    ) {
        Self.writer = writer
        NSSetUncaughtExceptionHandler { exception in
            // Deliberately minimal: this process is already dying. No allocation
            // beyond what the record needs, no async hop, no user-facing work.
            let report = CrashReport(
                kind: .uncaughtException,
                timestamp: Date(),
                appVersion: Self.appVersion,
                summary: exception.name.rawValue,
                detail: exception.reason ?? "",
                stack: exception.callStackSymbols
            )
            CrashSentinel.writer?.append(report)
        }
        MXMetricManager.shared.add(subscriber)
        Log.diagnostics.info("Crash sentinel installed at \(writer.fileURL.path, privacy: .public)")
    }

    /// Records written by earlier runs. Read at launch so a crash the user hit
    /// yesterday is still visible today.
    static func pendingReports() -> [CrashReport] {
        (writer ?? CrashLogWriter(directory: CrashLogWriter.defaultDirectory)).readAll()
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// MetricKit hands diagnostics over on a background queue; this just
    /// translates them into `CrashReport`s and appends.
    private final class MetricSubscriber: NSObject, MXMetricManagerSubscriber {
        func didReceive(_ payloads: [MXMetricPayload]) { /* aggregate metrics: not used */ }

        func didReceive(_ payloads: [MXDiagnosticPayload]) {
            for payload in payloads {
                append(payload.crashDiagnostics, kind: .crashDiagnostic)
                append(payload.hangDiagnostics, kind: .hang)
                append(payload.diskWriteExceptionDiagnostics, kind: .diskWriteException)
                append(payload.cpuExceptionDiagnostics, kind: .cpuException)
            }
        }

        private func append(_ diagnostics: [MXDiagnostic]?, kind: CrashReport.Kind) {
            for diagnostic in diagnostics ?? [] {
                let report = CrashReport(
                    kind: kind,
                    timestamp: Date(),
                    appVersion: diagnostic.applicationVersion,
                    summary: String(describing: type(of: diagnostic)),
                    detail: String(decoding: diagnostic.jsonRepresentation(), as: UTF8.self),
                    stack: []
                )
                CrashSentinel.writer?.append(report)
            }
        }
    }
}
