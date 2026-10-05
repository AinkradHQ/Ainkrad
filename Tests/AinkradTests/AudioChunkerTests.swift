import Foundation
import Testing

@testable import Ainkrad

@Suite("AudioChunker")
struct AudioChunkerTests {
    @Test func shortFileIsOneChunk() {
        let chunks = AudioChunker.plan(totalDuration: 30, maxChunk: 120)
        #expect(chunks == [AudioChunker.Chunk(index: 0, start: 0, duration: 30)])
    }

    @Test func longFileSplitsContiguously() {
        let chunks = AudioChunker.plan(totalDuration: 300, maxChunk: 120)
        #expect(chunks.count == 3)
        #expect(chunks[0] == AudioChunker.Chunk(index: 0, start: 0, duration: 120))
        #expect(chunks[1] == AudioChunker.Chunk(index: 1, start: 120, duration: 120))
        #expect(chunks[2] == AudioChunker.Chunk(index: 2, start: 240, duration: 60))
    }

    @Test func nonPositiveDurationIsSingleWholeFileChunk() {
        #expect(
            AudioChunker.plan(totalDuration: 0, maxChunk: 120)
                == [AudioChunker.Chunk(index: 0, start: 0, duration: 0)])
    }
}
