import Foundation
import Testing

@testable import Ainkrad

@Suite("MultipartForm")
struct MultipartFormTests {
    @Test func encodesFieldsAndFile() {
        let body = MultipartForm.build(
            boundary: "B",
            fields: ["model": "whisper-1"],
            file: (name: "file", filename: "a.m4a", data: Data("AUDIO".utf8), contentType: "audio/m4a"))
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains("name=\"model\""))
        #expect(text.contains("whisper-1"))
        #expect(text.contains("filename=\"a.m4a\""))
        #expect(text.contains("Content-Type: audio/m4a"))
        #expect(text.contains("AUDIO"))
        #expect(text.hasSuffix("--B--\r\n"))
    }
}
