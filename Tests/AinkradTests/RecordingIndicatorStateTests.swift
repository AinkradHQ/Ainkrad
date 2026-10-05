import Foundation
import Testing

@testable import Ainkrad

@Suite("RecordingIndicatorState")
struct RecordingIndicatorStateTests {
    @Test func mapsStatusToVisual() {
        #expect(RecordingIndicatorState.from(.idle) == .hidden)
        #expect(RecordingIndicatorState.from(.recording) == .recording)
        #expect(RecordingIndicatorState.from(.transcribing) == .transcribing)
        #expect(RecordingIndicatorState.from(.failed("x")) == .error("x"))
    }
}
