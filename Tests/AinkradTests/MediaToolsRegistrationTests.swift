import Testing
import Foundation
import AinkradHostRuntime
@testable import Ainkrad

@Suite("MediaToolsRegistration")
@MainActor
struct MediaToolsRegistrationTests {
    private func makeImageTool() -> ImageGenerateTool {
        ImageGenerateTool(
            backend: OpenAIImageBackend(secrets: InMemorySecretStore(), http: URLSessionDataHTTPClient()),
            store: ScryStore(sessionID: "s"))
    }

    @Test func imageGenerateIsReadClass() {
        let registry = AgentToolRegistry(tools: [makeImageTool()])
        #expect(registry.tool(named: "image_generate")?.permission == .read)
    }

    @Test func imageGenerateExcludedFromUnattendedRegistries() {
        let tool = makeImageTool()
        #expect(AppEnvironment.isUnattendedNetworkTool(tool))
        let unattended = AgentToolRegistry(tools: [tool].filter { !AppEnvironment.isUnattendedNetworkTool($0) })
        #expect(unattended.tool(named: "image_generate") == nil)
    }

    @Test func speakIsReadClass() {
        let mediaStore = GeneratedMediaStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ainkrad-test-\(UUID().uuidString)", isDirectory: true))
        let registry = AgentToolRegistry(tools: [SpeakTool(synth: SystemSpeechSynthesizer(), mediaStore: mediaStore)])
        #expect(registry.tool(named: "speak")?.permission == .read)
    }
}
