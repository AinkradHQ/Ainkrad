import Testing

@testable import Ainkrad

@Suite("GeneratedImageView")
struct GeneratedImageViewTests {
    @Test func fileExtensionFromDataURLMime() {
        #expect(GeneratedImageView.fileExtension(for: "data:image/jpeg;base64,QQ==") == "jpg")
        #expect(GeneratedImageView.fileExtension(for: "data:image/gif;base64,QQ==") == "gif")
        #expect(GeneratedImageView.fileExtension(for: "data:image/webp;base64,QQ==") == "webp")
        #expect(GeneratedImageView.fileExtension(for: "data:image/png;base64,QQ==") == "png")
        #expect(GeneratedImageView.fileExtension(for: "not a data url") == "png")  // default
    }
}
