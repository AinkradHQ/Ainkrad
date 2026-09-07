import Testing
import Foundation
import AinkradSignal
import AinkradHostRuntime
@testable import Ainkrad

@MainActor
@Suite("SignalIngressCoordinator")
final class SignalIngressCoordinatorTests {
    private final class NullDeliverer: SignalDeliverer {
        func deliver(_ event: SignalEvent, to channels: Set<DeliveryChannel>) {}
    }
    private struct Ctx: SignalContextProviding {
        var deliveryContext = DeliveryContext(hostIsFrontmost: true, visibleAppIDs: [],
                                              systemDoNotDisturb: false, hostFocusMode: false)
    }

    private let url: URL
    private let center: SignalCenter
    private let registry: SignalTokenRegistry
    private let coordinator: SignalIngressCoordinator
    private let token: String

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("signal-\(UUID().uuidString).sqlite")
        center = SignalCenter(store: try SignalStore(url: url),
                              deliverer: NullDeliverer(), contextProvider: Ctx())
        registry = SignalTokenRegistry(secrets: InMemorySecretStore())
        token = registry.mint(for: .app(appID: "raven"))
        coordinator = SignalIngressCoordinator(center: center, tokens: registry,
                                               limiter: SignalRateLimiter(limit: 20, window: 10))
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    private func payload(token: String, kind: String = "build.failed",
                         title: String = "Build failed") -> Data {
        Data("""
        {"token":"\(token)","kind":"\(kind)","severity":"failure","title":"\(title)"}
        """.utf8)
    }

    @Test("a valid payload is stamped with the token's source and stored")
    func acceptsAndStamps() {
        #expect(coordinator.accept(payload(token: token)) == .accepted)
        #expect(center.recent.count == 1)
        #expect(center.recent[0].source == .app(appID: "raven"))
    }

    @Test("an unknown token is rejected and the feed records the rejection")
    func unknownTokenIsRejectedAndLogged() {
        #expect(coordinator.accept(payload(token: "forged")) == .rejected(.unknownToken))
        let events = center.recent
        #expect(events.count == 1)
        #expect(events[0].kind == "signal.rejected")
        #expect(events[0].source == .host, "the feed records its own abuse, attributed to the host")
        #expect(!(events[0].body ?? "").contains("forged"), "a token never appears in the feed")
        #expect(!(events[0].title).contains("forged"))
    }

    @Test("a rejected payload never becomes a real event")
    func rejectionStoresNoUserEvent() {
        _ = coordinator.accept(payload(token: "forged"))
        #expect(!center.recent.contains { $0.kind == "build.failed" })
    }

    @Test("repeated rejections from one peer coalesce instead of flooding")
    func rejectionsCoalesce() {
        for _ in 0..<5 { _ = coordinator.accept(payload(token: "forged")) }
        #expect(center.recent.filter { $0.kind == "signal.rejected" }.count == 1,
                "an attacker must not be able to flood the feed with rejection rows")
    }

    @Test("two different bad peers are reported separately, not merged")
    func distinctPeersDoNotCoalesce() {
        // Coalescing is keyed on the peer hash, so one forged token cannot hide
        // another. Keyed on the KIND alone, a second attacker would be silent.
        _ = coordinator.accept(payload(token: "forged-a"))
        _ = coordinator.accept(payload(token: "forged-b"))
        #expect(center.recent.filter { $0.kind == "signal.rejected" }.count == 2)
    }

    @Test("an oversized payload is rejected before the token is even consulted")
    func oversizedRejected() {
        let huge = Data(("{\"token\":\"\(token)\",\"kind\":\"test.event\",\"severity\":\"info\",\"title\":\""
                         + String(repeating: "x", count: 9000) + "\"}").utf8)
        guard case .rejected(let rejection) = coordinator.accept(huge) else {
            Issue.record("expected rejection"); return
        }
        if case .tooLarge = rejection {} else { Issue.record("expected .tooLarge, got \(rejection)") }
    }

    @Test("past the rate limit, events throttle into a single summary event")
    func throttling() {
        for i in 0..<25 { _ = coordinator.accept(payload(token: token, title: "e\(i)")) }
        let throttles = center.recent.filter { $0.kind == "signal.throttled" }
        #expect(throttles.count == 1)
        #expect(center.recent.filter { $0.kind == "build.failed" }.count <= 20)
    }

    @Test("a throttle summary is attributed to the host, not to the throttled source")
    func throttleSummaryIsHostAttributed() {
        // Otherwise the summary counts against the very limit that produced it,
        // and a throttled source can never be told it is throttled.
        for i in 0..<25 { _ = coordinator.accept(payload(token: token, title: "e\(i)")) }
        let summary = center.recent.first { $0.kind == "signal.throttled" }
        #expect(summary?.source == .host)
    }

    @Test("an invalid kind is rejected without reaching the feed as an event")
    func invalidKindRejected() {
        let result = coordinator.accept(payload(token: token, kind: "Not A Kind"))
        #expect(result == .rejected(.invalidKind("Not A Kind")))
        #expect(!center.recent.contains { $0.kind == "Not A Kind" })
    }
}
