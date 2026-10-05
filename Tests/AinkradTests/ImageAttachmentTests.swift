import Foundation
import Testing

@testable import Ainkrad

@Suite("ImageAttachment")
struct ImageAttachmentTests {
    @Test func loadsPNGFromDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        // 1x1 PNG header bytes are enough for media-type detection.
        try Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).write(to: url)
        let att = try ImageAttachment.from(fileURL: url)
        #expect(att.mediaType == "image/png")
        #expect(!att.base64.isEmpty)
    }

    @Test @MainActor func visionGateWarnsOnNonVisionModel() {
        // deepseek-chat has no .vision capability in the compiled catalog.
        let cat = ModelCatalog()
        #expect(visionGate(model: "deepseek-chat", catalog: cat, hasImage: true) != nil)
        #expect(visionGate(model: "gpt-5", catalog: cat, hasImage: true) == nil)
        #expect(visionGate(model: "deepseek-chat", catalog: cat, hasImage: false) == nil)
    }
}
