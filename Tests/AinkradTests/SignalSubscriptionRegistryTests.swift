import Testing
import Foundation
import AinkradAppKit
import AinkradSignal
@testable import Ainkrad

@MainActor
@Suite("SignalSubscriptionRegistry")
final class SignalSubscriptionRegistryTests {
    private final class SpyObserver: PluginSignalObserver {
        var received: [SignalEvent] = []
        func signalDidArrive(_ event: SignalEvent) { received.append(event) }
    }

    private func event(source: SignalSource, kind: String) -> SignalEvent {
        SignalEvent(source: source, kind: kind, severity: .info, title: "t")
    }

    @Test("an unapproved subscription delivers nothing")
    func unapprovedDeliversNothing() {
        let registry = SignalSubscriptionRegistry()
        registry.setDeclared(SignalSubscription.parse(["app:raven/build.*"]), for: "gitmage")
        let observer = SpyObserver()
        registry.register(observer: observer, appID: "gitmage")
        registry.fanOut(event(source: .app(appID: "raven"), kind: "build.failed"))
        #expect(observer.received.isEmpty, "declaring is not consenting; the user approves")
    }

    @Test("an approved subscription delivers matching events only")
    func approvedDeliversMatches() {
        let registry = SignalSubscriptionRegistry()
        registry.setDeclared(SignalSubscription.parse(["app:raven/build.*"]), for: "gitmage")
        registry.approve(appID: "gitmage")
        let observer = SpyObserver()
        registry.register(observer: observer, appID: "gitmage")

        registry.fanOut(event(source: .app(appID: "raven"), kind: "build.failed"))
        registry.fanOut(event(source: .app(appID: "raven"), kind: "session.done"))
        registry.fanOut(event(source: .app(appID: "quest"), kind: "build.failed"))

        #expect(observer.received.count == 1)
        #expect(observer.received[0].kind == "build.failed")
    }

    @Test("revocation stops delivery immediately")
    func revocation() {
        let registry = SignalSubscriptionRegistry()
        registry.setDeclared(SignalSubscription.parse(["host/run.*"]), for: "gitmage")
        registry.approve(appID: "gitmage")
        let observer = SpyObserver()
        registry.register(observer: observer, appID: "gitmage")
        registry.revoke(appID: "gitmage")
        registry.fanOut(event(source: .host, kind: "run.finished"))
        #expect(observer.received.isEmpty)
    }

    @Test("an app never receives its own events through a subscription")
    func noSelfDelivery() {
        let registry = SignalSubscriptionRegistry()
        registry.setDeclared(SignalSubscription.parse(["host/run.*"]), for: "gitmage")
        registry.approve(appID: "gitmage")
        let observer = SpyObserver()
        registry.register(observer: observer, appID: "gitmage")
        registry.fanOut(event(source: .app(appID: "gitmage"), kind: "run.finished"))
        #expect(observer.received.isEmpty, "own(limit:) is that path, not this one")
    }

    @Test("the observer is held weakly, so an unloaded app cannot be resurrected")
    func weakObserver() {
        let registry = SignalSubscriptionRegistry()
        registry.setDeclared(SignalSubscription.parse(["host/run.*"]), for: "gitmage")
        registry.approve(appID: "gitmage")
        do {
            let observer = SpyObserver()
            registry.register(observer: observer, appID: "gitmage")
        }
        registry.fanOut(event(source: .host, kind: "run.finished"))
        #expect(registry.liveObserverCountForTesting == 0)
    }

    @Test("approval survives a relaunch; a re-declared wider list does not")
    func approvalIsScopedToWhatWasApproved() {
        let registry = SignalSubscriptionRegistry()
        registry.setDeclared(SignalSubscription.parse(["host/run.*"]), for: "gitmage")
        registry.approve(appID: "gitmage")
        registry.setDeclared(SignalSubscription.parse(["host/run.*", "app:raven/build.*"]),
                             for: "gitmage")
        #expect(!registry.isApproved(appID: "gitmage"),
                "a widened subscription list is a new consent question")
    }

    @Test("reordering the same list does NOT re-prompt")
    func reorderKeepsApproval() {
        // Consent is about WHAT was approved, not the order it was written in.
        // Hashing the list would re-prompt on a cosmetic manifest edit, and a
        // permission prompt the user cannot explain is one they learn to click
        // through.
        let registry = SignalSubscriptionRegistry()
        registry.setDeclared(SignalSubscription.parse(["host/run.*", "app:raven/build.*"]),
                             for: "gitmage")
        registry.approve(appID: "gitmage")
        registry.setDeclared(SignalSubscription.parse(["app:raven/build.*", "host/run.*"]),
                             for: "gitmage")
        #expect(registry.isApproved(appID: "gitmage"))
    }

    @Test("narrowing the list does NOT re-prompt")
    func narrowingKeepsApproval() {
        // Strictly less access than the user already allowed. Re-asking would
        // train them to approve without reading.
        let registry = SignalSubscriptionRegistry()
        registry.setDeclared(SignalSubscription.parse(["host/run.*", "app:raven/build.*"]),
                             for: "gitmage")
        registry.approve(appID: "gitmage")
        registry.setDeclared(SignalSubscription.parse(["host/run.*"]), for: "gitmage")
        #expect(registry.isApproved(appID: "gitmage"))
    }

    @Test("a widened list delivers NOTHING at all until re-approved, not just the new part")
    func wideningSuspendsEverything() {
        // The safe direction: consent is for a list, and the list changed. An
        // app that widens its manifest must not keep its old access while the
        // question is outstanding, or widening becomes a way to stay half-live
        // without asking.
        let registry = SignalSubscriptionRegistry()
        registry.setDeclared(SignalSubscription.parse(["host/run.*"]), for: "gitmage")
        registry.approve(appID: "gitmage")
        let observer = SpyObserver()
        registry.register(observer: observer, appID: "gitmage")
        registry.setDeclared(SignalSubscription.parse(["host/run.*", "app:raven/build.*"]),
                             for: "gitmage")
        registry.fanOut(event(source: .host, kind: "run.finished"))
        #expect(observer.received.isEmpty)
    }

    @Test("approval and declarations round-trip through a store")
    func persistence() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("subs-\(UUID().uuidString.prefix(8)).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let first = SignalSubscriptionRegistry(store: SignalSubscriptionStore(url: url))
        first.setDeclared(SignalSubscription.parse(["host/run.*"]), for: "gitmage")
        first.approve(appID: "gitmage")

        let second = SignalSubscriptionRegistry(store: SignalSubscriptionStore(url: url))
        second.setDeclared(SignalSubscription.parse(["host/run.*"]), for: "gitmage")
        #expect(second.isApproved(appID: "gitmage"),
                "an approval the user gave must not be asked for again next launch")
    }
}
