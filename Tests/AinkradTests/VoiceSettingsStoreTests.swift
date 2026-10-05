import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@Suite("VoiceSettingsStore")
@MainActor
struct VoiceSettingsStoreTests {
    @Test func defaultsArePrivacyPreserving() {
        let s = VoiceSettingsStore(persistence: InMemoryPersistenceStore())
        #expect(s.document.backend == .onDevice)
        #expect(s.document.mode == .hold)
        #expect(s.document.autoSend == false)
        #expect(s.document.providerOptIn == false)
    }

    @Test func settersPersistAndReload() {
        let p = InMemoryPersistenceStore()
        let s = VoiceSettingsStore(persistence: p)
        s.setBackend(.provider)
        s.setAutoSend(true)
        s.setProviderOptIn(true)
        let id = UUID()
        s.setProviderConnection(id)
        let reloaded = VoiceSettingsStore(persistence: p)
        #expect(reloaded.document.backend == .provider)
        #expect(reloaded.document.autoSend)
        #expect(reloaded.document.providerOptIn)
        #expect(reloaded.document.providerConnectionID == id)
    }
}
