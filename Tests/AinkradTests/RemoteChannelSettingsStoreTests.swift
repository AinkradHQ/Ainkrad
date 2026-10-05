import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@MainActor
@Suite("RemoteChannelSettingsStore")
struct RemoteChannelSettingsStoreTests {
    @Test func defaultsOffWithNoToken() {
        let store = RemoteChannelSettingsStore(
            persistence: InMemoryPersistenceStore(),
            secrets: InMemorySecretStore())
        #expect(store.settings.enabled == false)
        #expect(store.token == nil)
    }

    @Test func persistsEnableAndPortButNotToken() {
        let persistence = InMemoryPersistenceStore()
        let secrets = InMemorySecretStore()
        let store = RemoteChannelSettingsStore(persistence: persistence, secrets: secrets)
        store.setEnabled(true)
        store.setPort(9191)
        let token = store.rotateToken()
        #expect(token.count >= 24)
        #expect(secrets.secret(for: RemoteChannelSettingsStore.tokenSecretID) == token)

        // token must NEVER be in the persisted document
        let reopened = RemoteChannelSettingsStore(persistence: persistence, secrets: InMemorySecretStore())
        #expect(reopened.settings.enabled)
        #expect(reopened.settings.port == 9191)
        #expect(reopened.token == nil)  // fresh keychain → no token leaked via JSON
    }

    @Test func clearTokenRemovesIt() {
        let secrets = InMemorySecretStore()
        let store = RemoteChannelSettingsStore(persistence: InMemoryPersistenceStore(), secrets: secrets)
        _ = store.rotateToken()
        store.clearToken()
        #expect(store.token == nil)
    }
}
