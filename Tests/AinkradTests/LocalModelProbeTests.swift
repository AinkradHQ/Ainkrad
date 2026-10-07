// Tests/AinkradTests/LocalModelProbeTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("LocalModelProbe")
@MainActor
struct LocalModelProbeTests {
    @Test func recognizesLocalConnections() {
        let probe = LocalModelProbe(catalog: ModelCatalogService(http: StubDataHTTPClient(status: 200, body: Data())))
        let ollama = Connection(
            id: UUID(), presetID: "ollama", kind: .openAICompatible,
            displayName: "Ollama", baseURL: "http://localhost:11434/v1", createdAt: Date())
        let lmStudio = Connection(
            id: UUID(), presetID: "custom", kind: .openAICompatible,
            displayName: "LM Studio", baseURL: "http://localhost:1234/v1", createdAt: Date())
        let openAI = Connection(
            id: UUID(), presetID: "openai", kind: .openAICompatible,
            displayName: "OpenAI", baseURL: "https://api.openai.com/v1", createdAt: Date())
        #expect(probe.isLocal(ollama))
        #expect(probe.isLocal(lmStudio))  // custom preset, localhost URL
        #expect(!probe.isLocal(openAI))
    }

    @Test func downServerReturnsEmptyNoHang() async {
        // A stub that throws simulates the server being down.
        let probe = LocalModelProbe(catalog: ModelCatalogService(http: ThrowingDataHTTPClient()))
        let c = Connection(
            id: UUID(), presetID: "ollama", kind: .openAICompatible,
            displayName: "Ollama", baseURL: "http://localhost:11434/v1", createdAt: Date())
        let models = await probe.availableModels(for: c, apiKey: "")
        #expect(models.isEmpty)
    }

    @Test func upServerListsModels() async {
        let body = #"{"data":[{"id":"llama3.2"},{"id":"qwen2.5-coder"}]}"#.data(using: .utf8)!
        let probe = LocalModelProbe(catalog: ModelCatalogService(http: StubDataHTTPClient(status: 200, body: body)))
        let c = Connection(
            id: UUID(), presetID: "ollama", kind: .openAICompatible,
            displayName: "Ollama", baseURL: "http://localhost:11434/v1", createdAt: Date())
        let models = await probe.availableModels(for: c, apiKey: "")
        #expect(models.contains("llama3.2"))
    }
}
