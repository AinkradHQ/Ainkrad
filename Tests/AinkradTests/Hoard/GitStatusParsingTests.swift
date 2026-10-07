import Foundation
import Testing

@testable import Ainkrad

@Suite("porcelain=v2 parsing")
struct GitStatusParsingTests {
    private let root = URL(fileURLWithPath: "/repo")

    @Test("extracts the branch from the header")
    func branch() {
        let status = parsePorcelainV2("# branch.oid abc\n# branch.head main\n", root: root)
        #expect(status.branch == "main")
    }

    @Test("a detached HEAD is a real branch value, not nil")
    func detachedHead() {
        let status = parsePorcelainV2("# branch.head (detached)\n", root: root)
        #expect(status.branch == "(detached)")
    }

    @Test("an ordinary modified file")
    func ordinaryModified() {
        let line = "1 .M N... 100644 100644 100644 abc def src/main.swift"
        let status = parsePorcelainV2(line, root: root)
        #expect(status.entries["src/main.swift"] == .modified)
    }

    @Test("staged and unstaged are distinguished by the XY columns")
    func stagedVsUnstaged() {
        let staged = parsePorcelainV2("1 M. N... 100644 100644 100644 a b staged.swift", root: root)
        #expect(staged.entries["staged.swift"] == .staged)

        let unstaged = parsePorcelainV2("1 .M N... 100644 100644 100644 a b work.swift", root: root)
        #expect(unstaged.entries["work.swift"] == .modified)
    }

    @Test("an added file")
    func added() {
        let status = parsePorcelainV2("1 A. N... 000000 100644 100644 a b new.swift", root: root)
        #expect(status.entries["new.swift"] == .added)
    }

    @Test("a deleted file")
    func deleted() {
        let status = parsePorcelainV2("1 .D N... 100644 100644 000000 a b gone.swift", root: root)
        #expect(status.entries["gone.swift"] == .deleted)
    }

    // A rename's path field is "new<TAB>old" — splitting on spaces alone would
    // silently key the entry by "new\told" and never match a row.
    @Test("a rename keys by the NEW path, split on the tab")
    func rename() {
        let line = "2 R. N... 100644 100644 100644 a b R100 new/path.swift\told/path.swift"
        let status = parsePorcelainV2(line, root: root)
        #expect(status.entries["new/path.swift"] == .renamed)
        #expect(status.entries["old/path.swift"] == nil)
    }

    @Test("an unmerged entry is conflicted")
    func unmerged() {
        let line = "u UU N... 100644 100644 100644 100644 a b c conflict.swift"
        let status = parsePorcelainV2(line, root: root)
        #expect(status.entries["conflict.swift"] == .conflicted)
    }

    @Test("untracked and ignored entries")
    func untrackedAndIgnored() {
        let status = parsePorcelainV2("? scratch.txt\n! build/output.o\n", root: root)
        #expect(status.entries["scratch.txt"] == .untracked)
        #expect(status.entries["build/output.o"] == .ignored)
    }

    @Test("paths containing spaces survive parsing")
    func pathWithSpaces() {
        let line = "1 .M N... 100644 100644 100644 a b My Documents/notes file.md"
        let status = parsePorcelainV2(line, root: root)
        #expect(status.entries["My Documents/notes file.md"] == .modified)
    }

    @Test("a clean repo yields no entries but still reports its branch")
    func cleanRepo() {
        let status = parsePorcelainV2("# branch.head develop\n", root: root)
        #expect(status.entries.isEmpty)
        #expect(status.branch == "develop")
    }

    // A future git adding a header must not blank the listing.
    @Test("unrecognised lines are skipped, not fatal")
    func garbageInput() {
        let status = parsePorcelainV2("garbage\n# future.header value\n\n1 malformed\n", root: root)
        #expect(status.entries.isEmpty)
    }

    // MARK: - Lookup

    @Test("status lookup maps an absolute URL to its relative entry")
    func lookupByURL() {
        let status = parsePorcelainV2("1 .M N... 100644 100644 100644 a b src/main.swift", root: root)
        #expect(status.status(for: URL(fileURLWithPath: "/repo/src/main.swift")) == .modified)
        #expect(status.status(for: URL(fileURLWithPath: "/repo/src/other.swift")) == nil)
    }

    @Test("a directory reports modified when anything beneath it is")
    func directoryRollUp() {
        let status = parsePorcelainV2("1 .M N... 100644 100644 100644 a b src/deep/main.swift", root: root)
        #expect(status.status(for: URL(fileURLWithPath: "/repo/src")) == .modified)
    }

    @Test("a URL outside the repo has no status")
    func outsideRepo() {
        let status = parsePorcelainV2("1 .M N... 100644 100644 100644 a b a.swift", root: root)
        #expect(status.status(for: URL(fileURLWithPath: "/elsewhere/a.swift")) == nil)
    }
}
