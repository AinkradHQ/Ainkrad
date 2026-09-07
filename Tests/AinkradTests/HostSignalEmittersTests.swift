import Testing
import Foundation
import AinkradSignal
import AinkradHostRuntime
@testable import Ainkrad

@Suite("Host signal emitters")
struct HostSignalEmittersTests {
    @Test("install success is a plain success, keyed so a retry cannot double the row")
    func installCompleted() {
        let draft = SignalDraft.appInstalled(displayName: "Raven")
        #expect(draft.kind == "install.completed")
        #expect(draft.severity == .success)
        #expect(draft.title == "Raven installed")
        #expect(draft.dedupeKey == "install:Raven")
        #expect(draft.importance == .normal)
    }

    @Test("install failure is urgent and carries the reason")
    func installFailed() {
        let draft = SignalDraft.appInstallFailed(displayName: "Raven", reason: "404 from catalog")
        #expect(draft.kind == "install.failed")
        #expect(draft.severity == .failure)
        #expect(draft.importance == .urgent, "a failed install is work the user must redo")
        #expect(draft.body == "404 from catalog")
    }

    @Test("update success and failure use their own kinds so rules can separate them")
    func updates() {
        #expect(SignalDraft.appUpdated(displayName: "Quest").kind == "update.completed")
        #expect(SignalDraft.appUpdateFailed(displayName: "Quest", reason: "x").kind == "update.failed")
        #expect(SignalDraft.appUpdateFailed(displayName: "Quest", reason: "x").severity == .failure)
    }

    @Test("a plugin that fails to load names the bundle and says what to try")
    func loadFailure() {
        let failure = PluginLoadFailure(
            url: URL(fileURLWithPath: "/tmp/Plugins/rune.bundle"),
            reason: "built against generation 8; this host supports 9")
        let draft = SignalDraft.pluginLoadFailed(failure)
        #expect(draft.kind == "plugin.load-failed")
        #expect(draft.severity == .failure)
        #expect(draft.importance == .urgent)
        #expect(draft.title.contains("rune"), "the bundle name is all we have — a failed load has no display name")
        #expect(draft.body?.contains("generation 8") == true)
        #expect(draft.dedupeKey == "loadfail:rune.bundle")
    }

    @Test("every emitter produces a kind the ingest layer accepts")
    func kindsAreValid() {
        let failure = PluginLoadFailure(url: URL(fileURLWithPath: "/tmp/a.bundle"), reason: "r")
        let drafts = [
            SignalDraft.appInstalled(displayName: "A"),
            SignalDraft.appInstallFailed(displayName: "A", reason: "r"),
            SignalDraft.appUpdated(displayName: "A"),
            SignalDraft.appUpdateFailed(displayName: "A", reason: "r"),
            SignalDraft.pluginLoadFailed(failure),
        ]
        // The bug this guards is precisely the one that bit `session.needsInput`:
        // a vocabulary that reads fine and is silently rejected at ingest.
        for draft in drafts {
            #expect(SignalKind.isValid(draft.kind), "invalid kind: \(draft.kind)")
        }
    }
}
