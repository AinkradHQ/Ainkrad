import Foundation
import Testing

@testable import Ainkrad

@Suite("Preview kind")
struct PreviewKindTests {
    private func entry(_ name: String, dir: Bool = false) -> FileEntry {
        FileEntry(
            url: URL(fileURLWithPath: "/x/\(name)"), name: name, isDirectory: dir,
            isSymlink: false, isHidden: name.hasPrefix("."), size: 0, modified: Date())
    }

    @Test("source files map to the code renderer with a language")
    func sourceFiles() {
        #expect(previewKind(for: entry("main.swift")) == .code(language: "swift"))
        #expect(previewKind(for: entry("app.tsx")) == .code(language: "typescript"))
        #expect(previewKind(for: entry("run.sh")) == .code(language: "bash"))
        #expect(previewKind(for: entry("config.yml")) == .code(language: "yaml"))
    }

    // The whole reason not to hand source to Quick Look: it renders flat,
    // unhighlighted monospace, which the kit's code block beats outright.
    @Test("source files never fall through to Quick Look")
    func sourceNeverQuickLook() {
        #expect(previewKind(for: entry("main.swift")) != .quickLook)
        #expect(previewKind(for: entry("index.js")) != .quickLook)
    }

    @Test("plain text files map to text")
    func textFiles() {
        #expect(previewKind(for: entry("notes.md")) == .text)
        #expect(previewKind(for: entry("output.log")) == .text)
    }

    @Test("images map to the image renderer")
    func images() {
        #expect(previewKind(for: entry("shot.png")) == .image)
        #expect(previewKind(for: entry("photo.HEIC".lowercased())) == .image)
    }

    @Test("documents and media fall through to Quick Look")
    func quickLookFallback() {
        #expect(previewKind(for: entry("paper.pdf")) == .quickLook)
        #expect(previewKind(for: entry("clip.mov")) == .quickLook)
    }

    @Test("directories preview as directories, not as errors")
    func directories() {
        #expect(previewKind(for: entry("src", dir: true)) == .directory)
    }

    // ".gitignore" has pathExtension "gitignore"; ".env" has none. Both are
    // named files, not typed ones, and both should read as text.
    @Test("extensionless dotfiles are recognised by name")
    func dotfiles() {
        #expect(previewKind(for: entry(".gitignore")) == .text)
        #expect(previewKind(for: entry(".env")) == .text)
    }

    @Test("an unknown binary extension previews as nothing rather than garbage")
    func unknown() {
        #expect(previewKind(for: entry("firmware.bin")) == PreviewKind.none)
        #expect(previewKind(for: entry("noextension")) == PreviewKind.none)
    }

    // MARK: - Text reading

    @Test("reads a text file up to the limit")
    func readsText() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("preview-\(UUID().uuidString).txt")
        try "hello world".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(previewText(at: url) == "hello world")
    }

    @Test("truncates rather than loading a huge file into the pane")
    func truncates() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("preview-\(UUID().uuidString).txt")
        try String(repeating: "a", count: 5_000).write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(previewText(at: url, limit: 100)?.count == 100)
    }

    @Test("binary content returns nil instead of replacement characters")
    func binaryReturnsNil() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("preview-\(UUID().uuidString).swift")
        try Data([0xFF, 0xFE, 0x00, 0x01, 0xFF]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(previewText(at: url) == nil)
    }

    @Test("a missing file returns nil rather than throwing")
    func missingFile() {
        #expect(previewText(at: URL(fileURLWithPath: "/nope-\(UUID().uuidString)")) == nil)
    }
}
