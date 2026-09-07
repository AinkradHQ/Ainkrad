import Foundation
import AinkradHostRuntime
import AinkradSignal

extension SignalDraft {
    /// Maps a finished `AgentRun` onto the feed.
    ///
    /// `dedupeKey` is the run id: `finish(_:outcome:)` is guarded against
    /// double-calling, but a coalescing key costs nothing and makes a
    /// duplicated delivery invisible to the user rather than a doubled row.
    static func runCompleted(_ run: AgentRun) -> SignalDraft {
        let kind: String
        let severity: SignalSeverity
        let title: String
        switch run.status {
        case .done:
            kind = "run.finished"; severity = .success; title = "Run finished"
        case .failed:
            kind = "run.failed"; severity = .failure; title = "Run failed"
        case .interrupted:
            kind = "run.interrupted"; severity = .warning; title = "Run interrupted"
        case .queued, .running, .paused:
            kind = "run.updated"; severity = .info; title = "Run update"
        }
        var body = String(run.prompt.prefix(80))
        if let result = run.result, !result.isEmpty {
            body += "\n" + result.prefix(120)
        }
        return SignalDraft(kind: kind, severity: severity, title: title, body: body,
                           importance: run.status == .failed ? .urgent : .normal,
                           dedupeKey: "run:\(run.id.uuidString)")
    }

    // MARK: - App store

    /// An app finished installing from the store.
    static func appInstalled(displayName: String) -> SignalDraft {
        SignalDraft(kind: "install.completed", severity: .success,
                    title: "\(displayName) installed", importance: .normal,
                    dedupeKey: "install:\(displayName)")
    }

    /// An install failed. `.urgent`: the user asked for this app and does not
    /// have it, which is work they must redo.
    static func appInstallFailed(displayName: String, reason: String) -> SignalDraft {
        SignalDraft(kind: "install.failed", severity: .failure,
                    title: "\(displayName) failed to install", body: reason,
                    importance: .urgent, dedupeKey: "installfail:\(displayName)")
    }

    static func appUpdated(displayName: String) -> SignalDraft {
        SignalDraft(kind: "update.completed", severity: .success,
                    title: "\(displayName) updated", importance: .normal,
                    dedupeKey: "update:\(displayName)")
    }

    /// Distinct kind from `install.failed` so a user can mute update noise
    /// without also muting the installs they explicitly asked for.
    static func appUpdateFailed(displayName: String, reason: String) -> SignalDraft {
        SignalDraft(kind: "update.failed", severity: .failure,
                    title: "\(displayName) failed to update", body: reason,
                    importance: .urgent, dedupeKey: "updatefail:\(displayName)")
    }

    /// An app declared subscription patterns the host could not parse.
    ///
    /// Reported because the alternative is silence: a typo'd pattern is
    /// dropped so the app still loads, and without this the developer's
    /// subscription simply never fires with nothing to explain it. Named
    /// patterns verbatim — the point is to show the author their own string.
    static func subscriptionsDropped(displayName: String, patterns: [String]) -> SignalDraft {
        SignalDraft(kind: "plugin.subscriptions-dropped", severity: .warning,
                    title: "\(displayName) declared notification access Ainkrad could not read",
                    body: "These entries were ignored: " + patterns.joined(separator: ", ")
                        + ". The app still works; it just will not receive those notifications.",
                    importance: .background,
                    dedupeKey: "subsdropped:\(displayName)")
    }

    /// External ingress could not start.
    ///
    /// Recorded rather than only logged, because the consequence is otherwise
    /// invisible: `ainkrad notify`, Claude Code's hook and any CI script would
    /// post into a socket that is not there, succeed quietly (they exit 0 by
    /// design), and the user would conclude notifications are broken with
    /// nothing anywhere to say why.
    ///
    /// `.warning`, not `.failure`: in-process notifications from the host and
    /// every installed app are unaffected. This is one path being unavailable,
    /// not the feature being down.
    static func externalIngressUnavailable(reason: String) -> SignalDraft {
        SignalDraft(kind: "signal.ingress-unavailable", severity: .warning,
                    title: "Notifications from scripts and hooks are unavailable",
                    body: "The local notification socket could not be opened, so "
                        + "`ainkrad notify` and anything using it cannot reach the feed. "
                        + "Notifications from Ainkrad and its apps still work. \(reason)",
                    importance: .normal, dedupeKey: "ingress-unavailable")
    }

    /// A plugin bundle failed to load at launch.
    ///
    /// Named by BUNDLE, not display name: a bundle that failed to load never
    /// gave us its metadata, so the file name is genuinely all we have. This is
    /// almost always a pin mismatch — the host embeds one copy of the SDK and a
    /// plugin built against a newer revision dies at `Bundle.load()` — so the
    /// loader's reason goes in the body verbatim rather than being summarised
    /// into something friendlier and less useful.
    static func pluginLoadFailed(_ failure: PluginLoadFailure) -> SignalDraft {
        let bundle = failure.url.lastPathComponent
        return SignalDraft(kind: "plugin.load-failed", severity: .failure,
                           title: "\(bundle) failed to load", body: failure.reason,
                           importance: .urgent, dedupeKey: "loadfail:\(bundle)")
    }
}
