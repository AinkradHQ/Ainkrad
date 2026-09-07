import Foundation
import Testing
@testable import Ainkrad

@Suite("CrashReport")
struct CrashReportTests {
    private func sample(kind: CrashReport.Kind = .uncaughtException) -> CrashReport {
        CrashReport(
            kind: kind,
            timestamp: Date(timeIntervalSince1970: 1_757_116_800),
            appVersion: "1.4.2",
            summary: "NSInvalidArgumentException",
            detail: "-[NSNull length]: unrecognized selector",
            stack: ["0 Ainkrad 0x1", "1 AppKit 0x2"]
        )
    }

    @Test func ndjsonLineIsASingleLineTerminatedByNewline() throws {
        let data = try sample().ndjsonLine()
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.hasSuffix("\n"))
        // Exactly one newline: the terminator. A pretty-printed encoder would
        // break the append-only NDJSON file for every later reader.
        #expect(text.filter { $0 == "\n" }.count == 1)
    }

    @Test func roundTripsThroughNDJSON() throws {
        let original = sample()
        let decoded = try CrashReport.decode(ndjsonLine: original.ndjsonLine())
        #expect(decoded == original)
    }

    @Test func everyKindRoundTrips() throws {
        for kind in [CrashReport.Kind.uncaughtException, .hang, .diskWriteException,
                     .cpuException, .crashDiagnostic] {
            let decoded = try CrashReport.decode(ndjsonLine: sample(kind: kind).ndjsonLine())
            #expect(decoded.kind == kind)
        }
    }

    @Test func decodingGarbageThrowsRatherThanTrapping() {
        #expect(throws: (any Error).self) {
            try CrashReport.decode(ndjsonLine: Data("not json".utf8))
        }
    }
}
