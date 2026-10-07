import Foundation
import Testing

@testable import Ainkrad

@Suite("SeatbeltProfileGenerator")
struct SeatbeltProfileGeneratorTests {
    @Test func denyByDefaultHeader() throws {
        let sbpl = try SeatbeltProfileGenerator.generate(
            fs: FilesystemPolicy(readablePaths: [], writablePaths: []),
            network: .off, workspacePath: "/ws")
        #expect(sbpl.contains("(deny default)"))
    }

    @Test func networkOffDeniesNetwork() throws {
        let sbpl = try SeatbeltProfileGenerator.generate(
            fs: FilesystemPolicy(readablePaths: [], writablePaths: []),
            network: .off, workspacePath: "/ws")
        #expect(sbpl.contains("(deny network*)"))
        #expect(!sbpl.contains("(allow network*)"))
    }

    @Test func networkOnAllowsNetwork() throws {
        let sbpl = try SeatbeltProfileGenerator.generate(
            fs: FilesystemPolicy(readablePaths: [], writablePaths: []),
            network: .on, workspacePath: "/ws")
        #expect(sbpl.contains("(allow network*)"))
    }

    @Test func networkAllowListDeniesAtSBPLLayer() throws {
        // SBPL cannot filter by hostname; an allow-list must fail-closed here —
        // hostname enforcement belongs to a higher layer (proxy/DNS), not yet built.
        let sbpl = try SeatbeltProfileGenerator.generate(
            fs: FilesystemPolicy(readablePaths: [], writablePaths: []),
            network: .allowList(["example.com"]), workspacePath: "/ws")
        #expect(sbpl.contains("(deny network*)"))
        #expect(!sbpl.contains("(allow network*)"))
    }

    @Test func expandsWorkspacePlaceholderIntoWriteRule() throws {
        let sbpl = try SeatbeltProfileGenerator.generate(
            fs: FilesystemPolicy(readablePaths: ["<workspace>"], writablePaths: ["<workspace>"]),
            network: .off, workspacePath: "/Users/x/proj")
        #expect(sbpl.contains("(subpath \"/Users/x/proj\")"))
        #expect(sbpl.contains("(allow file-write*"))
    }

    @Test func readOnlyProfileHasNoWriteRule() throws {
        let sbpl = try SeatbeltProfileGenerator.generate(
            fs: FilesystemPolicy(readablePaths: ["<workspace>"], writablePaths: []),
            network: .off, workspacePath: "/ws")
        #expect(!sbpl.contains("(allow file-write*"))
    }

    @Test func readablePathProducesExactlyThatSubpathAllowAndNothingBroader() throws {
        let sbpl = try SeatbeltProfileGenerator.generate(
            fs: FilesystemPolicy(readablePaths: ["/Users/x/only-this"], writablePaths: []),
            network: .off, workspacePath: "/ws")
        #expect(sbpl.contains("(allow file-read* (subpath \"/Users/x/only-this\"))"))
        // A sibling path that was never listed must not appear anywhere in the output.
        #expect(!sbpl.contains("/Users/x/only-this-sibling"))
        #expect(!sbpl.contains("(subpath \"/Users/x\")"))
        #expect(!sbpl.contains("(subpath \"/\")"))
    }

    @Test func unlistedPathIsNotGranted() throws {
        let sbpl = try SeatbeltProfileGenerator.generate(
            fs: FilesystemPolicy(readablePaths: ["/Users/x/allowed"], writablePaths: []),
            network: .off, workspacePath: "/ws")
        #expect(!sbpl.contains("/Users/x/not-listed"))
    }

    @Test func quoteInPathIsEscapedAndDoesNotBreakOrInjectSBPL() throws {
        let evil = "/Users/x/\" (allow file-read* (subpath \"/"
        let sbpl = try SeatbeltProfileGenerator.generate(
            fs: FilesystemPolicy(readablePaths: [evil], writablePaths: []),
            network: .off, workspacePath: "/ws")
        // The raw, unescaped quote must never appear unescaped inside a literal —
        // every quote in the source path must be preceded by a backslash in output.
        #expect(sbpl.contains("\\\""))
        // The injected "(allow file-read*" text inside the malicious path is
        // embedded as data inside one quoted literal, not as a separate
        // top-level s-expression — count only rules that actually START a
        // line (a real break-out would require an unescaped literal newline,
        // which is rejected separately by `pathWithNewlineIsRejectedFailClosed`).
        let allowReadLineCount = sbpl.split(separator: "\n")
            .filter { $0.hasPrefix("(allow file-read*") }.count
        #expect(allowReadLineCount == SeatbeltProfileGenerator.systemReadPaths.count + 1)
    }

    @Test func backslashInPathIsEscaped() throws {
        let tricky = "/Users/x/back\\slash"
        let sbpl = try SeatbeltProfileGenerator.generate(
            fs: FilesystemPolicy(readablePaths: [tricky], writablePaths: []),
            network: .off, workspacePath: "/ws")
        #expect(sbpl.contains("\\\\"))
    }

    @Test func pathWithNewlineIsRejectedFailClosed() throws {
        let malicious = "/Users/x/evil\n(allow file-read* (subpath \"/\""
        #expect(throws: BackendError.self) {
            _ = try SeatbeltProfileGenerator.generate(
                fs: FilesystemPolicy(readablePaths: [malicious], writablePaths: []),
                network: .off, workspacePath: "/ws")
        }
    }

    @Test func relativePathIsRejectedFailClosed() throws {
        #expect(throws: BackendError.self) {
            _ = try SeatbeltProfileGenerator.generate(
                fs: FilesystemPolicy(readablePaths: ["relative/path"], writablePaths: []),
                network: .off, workspacePath: "/ws")
        }
    }

    @Test func emptyPathIsRejectedFailClosed() throws {
        #expect(throws: BackendError.self) {
            _ = try SeatbeltProfileGenerator.generate(
                fs: FilesystemPolicy(readablePaths: [""], writablePaths: []),
                network: .off, workspacePath: "/ws")
        }
    }

    @Test func generationIsDeterministicForSameProfile() throws {
        let fs = FilesystemPolicy(
            readablePaths: ["<workspace>", "/opt/tools"],
            writablePaths: ["<workspace>"])
        let a = try SeatbeltProfileGenerator.generate(fs: fs, network: .on, workspacePath: "/Users/x/proj")
        let b = try SeatbeltProfileGenerator.generate(fs: fs, network: .on, workspacePath: "/Users/x/proj")
        #expect(a == b)
    }
}
