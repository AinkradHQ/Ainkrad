import Testing
import Foundation
import AinkradHostRuntime
@testable import Ainkrad

@Suite("ToolCallImageLookup")
@MainActor
struct ToolCallImageLookupTests {
    @Test func extractsFirstUUID() {
        let id = "9F1C2D3E-4A5B-6C7D-8E9F-0A1B2C3D4E5F"
        #expect(ToolCallImageLookup.firstUUID(in: "Rendered generated image as scry element \(id).") == id)
        #expect(ToolCallImageLookup.firstUUID(in: "no id here") == nil)
    }

    @Test func resolvesImageBodyFromResultText() {
        let store = ScryStore(sessionID: "s")
        let dataURL = "data:image/png;base64,QUJD"
        let id = store.add(ScryElement(id: UUID().uuidString, kind: .image, title: "x", body: dataURL))
        let resultText = "Rendered generated image as scry element \(id)."
        #expect(ToolCallImageLookup.canvasImageDataURL(resultText: resultText, store: store) == dataURL)
    }

    @Test func returnsNilForMissingOrNonImage() {
        let store = ScryStore(sessionID: "s")
        #expect(ToolCallImageLookup.canvasImageDataURL(resultText: nil, store: store) == nil)
        #expect(ToolCallImageLookup.canvasImageDataURL(
            resultText: "no uuid", store: store) == nil)
        // element exists but is not an image kind
        let id = store.add(ScryElement(id: UUID().uuidString, kind: .card, title: "t", body: "hi"))
        #expect(ToolCallImageLookup.canvasImageDataURL(
            resultText: "element \(id)", store: store) == nil)
    }
}
