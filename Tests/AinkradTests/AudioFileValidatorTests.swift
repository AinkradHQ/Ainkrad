import Foundation
import Testing

@testable import Ainkrad

@Suite("AudioFileValidator")
struct AudioFileValidatorTests {
    @Test func acceptsSupportedAudio() throws {
        try AudioFileValidator.validate(fileName: "memo.m4a", byteCount: 1_000)
        try AudioFileValidator.validate(fileName: "Voice 001.WAV", byteCount: 1_000)
    }

    @Test func rejectsUnsupportedFormat() {
        #expect(throws: TranscriptionError.self) {
            try AudioFileValidator.validate(fileName: "notes.pdf", byteCount: 10)
        }
    }

    @Test func rejectsOversized() {
        #expect(throws: TranscriptionError.self) {
            try AudioFileValidator.validate(fileName: "big.m4a", byteCount: AudioFileValidator.maxBytes + 1)
        }
    }
}
