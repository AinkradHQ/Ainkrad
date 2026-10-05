import Foundation
import Testing

@testable import Ainkrad

final class FakeCaptureSession: AudioCaptureSession, @unchecked Sendable {
    private(set) var isRecording = false
    var startError: Error?
    var producedURL: URL? = URL(fileURLWithPath: "/tmp/fake-capture.m4a")
    var startCount = 0
    var stopCount = 0
    func start() throws {
        if let startError { throw startError }
        isRecording = true
        startCount += 1
    }
    func stop() -> URL? {
        isRecording = false
        stopCount += 1
        return producedURL
    }
}

@Suite("AudioCaptureSession contract")
struct AudioCaptureSessionContractTests {
    @Test func startThenStopTogglesRecording() throws {
        let c = FakeCaptureSession()
        try c.start()
        #expect(c.isRecording)
        let url = c.stop()
        #expect(!c.isRecording)
        #expect(url != nil)
    }

    @Test func initialStateIsNotRecording() {
        let c = FakeCaptureSession()
        #expect(!c.isRecording)
    }

    @Test func stopReturnsNilWhenNothingCaptured() {
        let c = FakeCaptureSession()
        c.producedURL = nil
        let url = c.stop()
        #expect(url == nil)
    }
}
