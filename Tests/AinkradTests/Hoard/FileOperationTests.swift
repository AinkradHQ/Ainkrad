import Foundation
import Testing

@testable import Ainkrad

@Suite("FileOperation")
struct FileOperationTests {
    @Test("keep-both suffixes until the name is free")
    func uniqueName() {
        #expect(uniqueDestinationName(for: "a.txt", existing: []) == "a.txt")
        #expect(uniqueDestinationName(for: "a.txt", existing: ["a.txt"]) == "a 2.txt")
        #expect(uniqueDestinationName(for: "a.txt", existing: ["a.txt", "a 2.txt"]) == "a 3.txt")
    }

    @Test("extensionless names still suffix correctly")
    func uniqueNameNoExtension() {
        #expect(uniqueDestinationName(for: "README", existing: ["README"]) == "README 2")
    }

    @Test("dotfiles keep their leading dot")
    func uniqueNameDotfile() {
        // ".gitignore" is a NAME, not an extension — suffixing must not
        // produce " 2.gitignore".
        #expect(uniqueDestinationName(for: ".gitignore", existing: [".gitignore"]) == ".gitignore 2")
    }

    @Test("multi-dot names suffix before the last extension only")
    func uniqueNameMultiDot() {
        #expect(uniqueDestinationName(for: "a.tar.gz", existing: ["a.tar.gz"]) == "a.tar 2.gz")
    }
}
