import Foundation
import Testing

@testable import Ainkrad

@Suite("Hoard tool scope")
struct HoardToolScopeTests {
    private let roots = [URL(fileURLWithPath: "/Users/test/project")]
    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    @Test("a path inside an open pane is allowed")
    func insideOpenRoot() {
        #expect(
            HoardToolScope.decide(
                target: url("/Users/test/project/src/main.swift"),
                openRoots: roots, wasExplicitlyAbsolute: false) == .allowed)
    }

    @Test("the open root itself is allowed")
    func rootItself() {
        #expect(
            HoardToolScope.decide(
                target: url("/Users/test/project"),
                openRoots: roots, wasExplicitlyAbsolute: false) == .allowed)
    }

    // The core protection: an assistant misreading "clean up these files"
    // must fail closed rather than acting somewhere it inferred.
    @Test("an inferred path outside every pane is refused")
    func outsideRootsRefused() {
        let decision = HoardToolScope.decide(
            target: url("/Users/test/other/thing.txt"),
            openRoots: roots, wasExplicitlyAbsolute: false)
        #expect(decision != .allowed)
    }

    @Test("an EXPLICIT absolute path outside the panes is allowed")
    func explicitAbsoluteAllowed() {
        #expect(
            HoardToolScope.decide(
                target: url("/Users/test/other/thing.txt"),
                openRoots: roots, wasExplicitlyAbsolute: true) == .allowed)
    }

    @Test("system directories are refused even when explicit")
    func systemDirectoriesAlwaysRefused() {
        for path in ["/System/Library/x", "/usr/bin/git", "/bin/sh", "/Library/Preferences/x"] {
            #expect(
                HoardToolScope.decide(
                    target: url(path), openRoots: roots,
                    wasExplicitlyAbsolute: true) != .allowed,
                "\(path) must be refused")
        }
    }

    @Test("the filesystem root is refused even when explicit")
    func filesystemRootRefused() {
        #expect(
            HoardToolScope.decide(
                target: url("/"), openRoots: roots,
                wasExplicitlyAbsolute: true) != .allowed)
    }

    @Test("a path containing .. is refused rather than resolved")
    func traversalRefused() {
        let target = URL(fileURLWithPath: "/Users/test/project").appendingPathComponent("../../etc")
        #expect(
            HoardToolScope.decide(
                target: target, openRoots: roots,
                wasExplicitlyAbsolute: true) != .allowed)
    }

    @Test("with no panes open, only explicit absolute paths are reachable")
    func noOpenPanes() {
        #expect(
            HoardToolScope.decide(
                target: url("/Users/test/a.txt"), openRoots: [],
                wasExplicitlyAbsolute: false) != .allowed)
        #expect(
            HoardToolScope.decide(
                target: url("/Users/test/a.txt"), openRoots: [],
                wasExplicitlyAbsolute: true) == .allowed)
    }

    // A sibling whose name merely starts with the root's name is NOT inside it.
    @Test("prefix matching does not leak into sibling directories")
    func siblingPrefixNotInside() {
        #expect(!HoardToolScope.isInside("/Users/test/project-secrets/x", anyOf: roots))
        #expect(HoardToolScope.isInside("/Users/test/project/x", anyOf: roots))
    }
}
