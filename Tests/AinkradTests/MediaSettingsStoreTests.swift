import AinkradHostRuntime
import Testing

@testable import Ainkrad

@Suite("MediaSettingsStore")
@MainActor
struct MediaSettingsStoreTests {
    @Test func persistsProviderChoice() {
        let p = InMemoryPersistenceStore()
        MediaSettingsStore(persistence: p).setProvider("pollinations")
        #expect(MediaSettingsStore(persistence: p).document.provider == "pollinations")
    }

    @Test func persistsLocalSDURL() {
        let p = InMemoryPersistenceStore()
        MediaSettingsStore(persistence: p).setLocalSDURL("http://127.0.0.1:7860")
        #expect(MediaSettingsStore(persistence: p).document.localSDURL == "http://127.0.0.1:7860")
    }
}
