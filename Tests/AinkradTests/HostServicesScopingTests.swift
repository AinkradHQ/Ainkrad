import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

struct HostServicesScopingTests {
    @Test("an app cannot read another app's documents")
    func documentIsolation() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let a = ScopedPluginDocumentStore(directory: root.appendingPathComponent("appA"))
        let b = ScopedPluginDocumentStore(directory: root.appendingPathComponent("appB"))

        a.setData(Data("secret".utf8), forKey: "note")
        #expect(a.data(forKey: "note") == Data("secret".utf8))
        #expect(b.data(forKey: "note") == nil)
    }

    @Test("a document key cannot escape its app directory via traversal")
    func documentTraversalBlocked() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let a = ScopedPluginDocumentStore(directory: root.appendingPathComponent("appA"))
        a.setData(Data("x".utf8), forKey: "../../escape")
        // Nothing is written outside the app directory.
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("escape").path))
    }

    @Test("secrets are namespaced per app")
    func secretIsolation() {
        let backing = InMemorySecretStore()
        let a = ScopedPluginSecretStore(appID: "appA", backing: backing)
        let b = ScopedPluginSecretStore(appID: "appB", backing: backing)

        a.setSecret("token", forKey: "api")
        #expect(a.secret(forKey: "api") == "token")
        #expect(b.secret(forKey: "api") == nil)
        #expect(backing.secret(for: "appA/api") == "token")
    }

    @Test("secret keys cannot collide across appIDs that differ only by a dot")
    func secretKeyNoCollision() {
        let backing = InMemorySecretStore()
        let ab = ScopedPluginSecretStore(appID: "a.b", backing: backing)
        let a = ScopedPluginSecretStore(appID: "a", backing: backing)
        ab.setSecret("from-ab", forKey: "c")  // appID "a.b", key "c"
        a.setSecret("from-a", forKey: "b.c")  // appID "a",   key "b.c"
        // With a dot separator these both mapped to "a.b.c" and clobbered each other.
        #expect(ab.secret(forKey: "c") == "from-ab")
        #expect(a.secret(forKey: "b.c") == "from-a")
    }
}
