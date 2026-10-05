import Foundation
import Testing

@testable import Ainkrad

@MainActor
@Suite struct MentionFileReaderTests {
    private func tempFile(_ bytes: Data, ext: String = "txt") throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "." + ext)
        try bytes.write(to: url)
        return url.path
    }

    @Test func readsUTF8TextWithinCap() throws {
        let path = try tempFile(Data("hello mention".utf8))
        #expect(MentionFileReader.read(path: path) == "hello mention")
    }

    @Test func returnsNilForMissingFile() {
        #expect(MentionFileReader.read(path: "/no/such/file.swift") == nil)
    }

    @Test func returnsNilForNonUTF8Binary() throws {
        let path = try tempFile(Data([0xFF, 0xFE, 0x00, 0x01]))
        #expect(MentionFileReader.read(path: path) == nil)
    }

    @Test func returnsNilWhenOverCap() throws {
        let big = Data(repeating: 0x41, count: ReadFileTool.maxBytes + 1)
        let path = try tempFile(big)
        #expect(MentionFileReader.read(path: path) == nil)
    }

    @Test func mentionDefaultsToEmbed() {
        #expect(ComposerMention(path: "/a.swift").mode == .embed)
    }
}
