import Foundation
import Testing

@testable import Ainkrad

@Suite @MainActor struct ComposerMentionSendTests {
    private func tempFile(_ text: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".swift")
        try Data(text.utf8).write(to: url)
        return url.path
    }
    @Test func outgoingTextEmbedsEmbedModeMention() throws {
        let path = try tempFile("struct A {}")
        let out = SageComposerBar.outgoingText(
            draft: "explain @\(path)",
            mentions: [ComposerMention(path: path, mode: .embed)])
        #expect(out.contains("<mentioned_files>"))
        #expect(out.contains("struct A {}"))
    }
    @Test func outgoingTextLeavesReferenceModeAsPathOnly() throws {
        let path = try tempFile("struct A {}")
        let out = SageComposerBar.outgoingText(
            draft: "explain @\(path)",
            mentions: [ComposerMention(path: path, mode: .reference)])
        #expect(out == "explain @\(path)")
    }
}
