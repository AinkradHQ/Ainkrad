import Foundation
import Testing
@testable import Ainkrad

@Suite("StreamCoalescer")
struct StreamCoalescerTests {
    @Test func publishesTheFirstTimeItIsAsked() {
        var coalescer = StreamCoalescer(interval: .milliseconds(50))
        let start = ContinuousClock.now
        let published = coalescer.shouldPublish(at: start)
        #expect(published)
    }

    @Test func suppressesASecondCallInsideTheWindow() {
        var coalescer = StreamCoalescer(interval: .milliseconds(50))
        let start = ContinuousClock.now
        _ = coalescer.shouldPublish(at: start)
        let at10ms = coalescer.shouldPublish(at: start.advanced(by: .milliseconds(10)))
        #expect(!at10ms)
        let at49ms = coalescer.shouldPublish(at: start.advanced(by: .milliseconds(49)))
        #expect(!at49ms)
    }

    @Test func publishesOnceTheWindowHasElapsed() {
        var coalescer = StreamCoalescer(interval: .milliseconds(50))
        let start = ContinuousClock.now
        _ = coalescer.shouldPublish(at: start)
        let published = coalescer.shouldPublish(at: start.advanced(by: .milliseconds(50)))
        #expect(published)
    }

    @Test func aBurstOfOneHundredCallsInsideOneWindowPublishesOnce() {
        var coalescer = StreamCoalescer(interval: .milliseconds(50))
        let start = ContinuousClock.now
        var published = 0
        for offset in 0..<100 where coalescer.shouldPublish(
            at: start.advanced(by: .microseconds(offset * 100))) {
            published += 1
        }
        // 100 calls spread over 10ms — one window.
        #expect(published == 1)
    }

    @Test func resetAllowsAnImmediatePublishAgain() {
        var coalescer = StreamCoalescer(interval: .milliseconds(50))
        let start = ContinuousClock.now
        _ = coalescer.shouldPublish(at: start)
        coalescer.reset(at: start.advanced(by: .milliseconds(1)))
        let published = coalescer.shouldPublish(at: start.advanced(by: .milliseconds(1)))
        #expect(published)
    }

    @Test func defaultIntervalIsFiftyMilliseconds() {
        #expect(StreamCoalescer.publishInterval == .milliseconds(50))
    }
}
