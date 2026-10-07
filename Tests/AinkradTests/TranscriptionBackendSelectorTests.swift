import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

private struct StubService: TranscriptionService {
    let tag: String
    func transcribe(audio: Data, fileName: String, localeIdentifier: String?) async throws -> TranscriptionResult {
        TranscriptionResult(text: tag)
    }
}
private struct StubAvail: SpeechRecognizerAvailability {
    let ok: Bool
    func isAvailable(localeIdentifier: String) -> Bool { ok }
}

@Suite("TranscriptionBackendSelector")
@MainActor
struct TranscriptionBackendSelectorTests {
    private func settings(_ configure: (VoiceSettingsStore) -> Void) -> VoiceSettingsStore {
        let s = VoiceSettingsStore(persistence: InMemoryPersistenceStore())
        configure(s)
        return s
    }

    @Test func onDeviceWhenAvailable() throws {
        let sel = TranscriptionBackendSelector(
            settings: settings { _ in }, onDevice: StubService(tag: "local"),
            providerFactory: { nil }, availability: StubAvail(ok: true))
        #expect(try sel.resolve().kind == .onDevice)
    }

    @Test func fallsBackToProviderWithNoticeWhenOnDeviceUnavailable() throws {
        let sel = TranscriptionBackendSelector(
            settings: settings { $0.setProviderOptIn(true) },
            onDevice: StubService(tag: "local"),
            providerFactory: { StubService(tag: "cloud") }, availability: StubAvail(ok: false))
        let r = try sel.resolve()
        #expect(r.kind == .provider)
        #expect(r.notice != nil)
    }

    @Test func onDeviceUnavailableAndNoProviderThrows() {
        let sel = TranscriptionBackendSelector(
            settings: settings { _ in }, onDevice: StubService(tag: "local"),
            providerFactory: { nil }, availability: StubAvail(ok: false))
        #expect(throws: TranscriptionError.self) { _ = try sel.resolve() }
    }

    @Test func providerSelectedButNotOptedInThrows() {
        let sel = TranscriptionBackendSelector(
            settings: settings { $0.setBackend(.provider) },
            onDevice: StubService(tag: "local"),
            providerFactory: { StubService(tag: "cloud") }, availability: StubAvail(ok: true))
        #expect(throws: TranscriptionError.self) { _ = try sel.resolve() }
    }

    @Test func providerSelectedAndOptedIn() throws {
        let sel = TranscriptionBackendSelector(
            settings: settings {
                $0.setBackend(.provider)
                $0.setProviderOptIn(true)
            },
            onDevice: StubService(tag: "local"),
            providerFactory: { StubService(tag: "cloud") }, availability: StubAvail(ok: true))
        #expect(try sel.resolve().kind == .provider)
    }
}
