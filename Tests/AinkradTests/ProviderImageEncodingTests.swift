import Foundation
import Testing

@testable import Ainkrad

@Suite("Provider image encoding")
struct ProviderImageEncodingTests {
    @Test func openAIEncodesImageURLBlock() {
        let msg = AgentMessage(
            role: .user, content: [.image(mediaType: "image/png", base64: "AAAA"), .text("what is this")])
        let wire = OpenAICompatibleProvider.wireContentForTesting(msg)
        // Expect a content array carrying an image_url data URI.
        #expect(wire.contains { ($0["type"] as? String) == "image_url" })
    }

    @Test func geminiEncodesImageBlockAsCamelCaseInlineData() {
        let msg = AgentMessage(
            role: .user, content: [.image(mediaType: "image/png", base64: "AAAA"), .text("what is this")])
        let parts = GeminiProvider.wireContentForTesting(msg)
        // Expect camelCase `inlineData`/`mimeType` keys matching the live Gemini REST API —
        // the snake_case `inline_data`/`mime_type` form is silently ignored by the API.
        let inlineData = parts.compactMap { $0["inlineData"] as? [String: Any] }.first
        #expect(inlineData != nil)
        #expect(inlineData?["mimeType"] as? String == "image/png")
        #expect(inlineData?["data"] as? String == "AAAA")
    }
}
