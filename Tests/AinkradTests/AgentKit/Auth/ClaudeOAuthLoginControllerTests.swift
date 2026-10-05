import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

@MainActor @Suite struct ClaudeOAuthLoginControllerTests {
    private func makeController() -> (ClaudeOAuthLoginController, OAuthCredentialStore) {
        let secrets = InMemorySecretStore()
        let persistence = InMemoryPersistenceStore()
        let transport = ArrayTokenTransport(responses: [])
        let flow = ClaudeOAuthFlow(transport: transport, clientVersion: "2.1.74")
        let store = OAuthCredentialStore(
            persistence: persistence, secrets: secrets,
            flow: flow, now: { Date(timeIntervalSince1970: 1000) })
        return (ClaudeOAuthLoginController(store: store, flow: flow), store)
    }

    @Test func pasteCodeWithUnparseableStringSetsErrorMessageAndStoresNothing() async {
        let (controller, store) = makeController()
        let conn = Connection(
            id: UUID(), presetID: "claude", kind: .claude,
            displayName: "Claude", baseURL: "https://api.anthropic.com",
            createdAt: Date(timeIntervalSince1970: 1000), authMode: .subscription)
        await controller.pasteCode("   ", for: conn)
        #expect(controller.errorMessage != nil)
        #expect(store.account(for: conn.id) == nil)
    }

    @Test func parsesHashDelimitedCodeState() {
        let r = ClaudeOAuthLoginController.parsePastedCode("THECODE#THESTATE")
        #expect(r == CallbackResult(code: "THECODE", state: "THESTATE"))
    }

    @Test func parsesFullRedirectURLPaste() {
        let r = ClaudeOAuthLoginController.parsePastedCode("http://localhost:53692/callback?code=C&state=S")
        #expect(r == CallbackResult(code: "C", state: "S"))
    }

    @Test func returnsNilForEmpty() {
        #expect(ClaudeOAuthLoginController.parsePastedCode("   ") == nil)
    }
}
