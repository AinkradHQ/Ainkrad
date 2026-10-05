import Foundation
import Testing

@testable import Ainkrad

@Suite("ScryImageDecoding")
struct ScryImageDecodingTests {
    private let pngB64 = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).base64EncodedString()

    @Test func parsesBase64DataURL() {
        let body = "data:image/jpeg;base64,\(pngB64)"
        #expect(ScryImageDecoding.base64Payload(body) == Data(base64Encoded: pngB64))
    }

    @Test func rejectsNonDataAndMalformed() {
        #expect(ScryImageDecoding.base64Payload("https://example.com/x.png") == nil)
        #expect(ScryImageDecoding.base64Payload("data:image/png,notbase64") == nil)  // no ;base64
        #expect(ScryImageDecoding.base64Payload("data:image/png;base64,") == nil)  // empty payload
        #expect(ScryImageDecoding.base64Payload("") == nil)
    }
}
