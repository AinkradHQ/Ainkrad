import Foundation
import Testing

@testable import Ainkrad

@Suite("Transcription value types")
struct TranscriptionValueTypesTests {
    @Test func backendKindCodableRoundTrips() throws {
        for kind in TranscriptionBackendKind.allCases {
            let data = try JSONEncoder().encode(kind)
            #expect(try JSONDecoder().decode(TranscriptionBackendKind.self, from: data) == kind)
        }
    }

    @Test func modeCodableRoundTrips() throws {
        for mode in PushToTalkMode.allCases {
            let data = try JSONEncoder().encode(mode)
            #expect(try JSONDecoder().decode(PushToTalkMode.self, from: data) == mode)
        }
    }

    @Test func resultDefaultsToFinal() {
        #expect(TranscriptionResult(text: "hi").isFinal)
    }
}
