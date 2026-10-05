import AinkradHostRuntime
import Foundation
import Testing

@testable import Ainkrad

/// Measurement, not assertion — turns the Wave 2 transcript claim into a number.
@MainActor
@Suite("Transcript rebuild cost", .serialized)
struct TranscriptBenchmark {

    @Test("Measure per-chunk timeline rebuild vs memoized")
    func measureRebuild() {
        // A long-but-plausible session: 60 turns.
        var messages: [AgentMessage] = []
        for i in 0..<60 {
            messages.append(AgentMessage(role: .user, content: [.text("question \(i)")]))
            messages.append(
                AgentMessage(
                    role: .assistant,
                    content: [.text(String(repeating: "answer text ", count: 60))]))
        }

        // A streamed reply re-evaluates `body` per chunk. 400 chunks is a
        // medium-length answer.
        let chunks = 400

        let uncachedStart = Date()
        for _ in 0..<chunks { _ = TranscriptTimelineBuilder.build(from: messages) }
        let uncached = Date().timeIntervalSince(uncachedStart)

        let cache = TranscriptTimelineCache()
        let cachedStart = Date()
        for _ in 0..<chunks { _ = cache.items(for: messages) }
        let cached = Date().timeIntervalSince(cachedStart)

        let uncachedMs = uncached / Double(chunks) * 1000
        let cachedMs = cached / Double(chunks) * 1000
        print("")
        print("── Transcript timeline, 120 messages x \(chunks) streamed chunks ──")
        print(
            "  rebuild per chunk (old): \(String(format: "%.3f", uncached))s  (\(String(format: "%.2f", uncachedMs))ms/chunk)"
        )
        print(
            "  memoized          (new): \(String(format: "%.3f", cached))s  (\(String(format: "%.2f", cachedMs))ms/chunk)"
        )
        print("  speedup: \(String(format: "%.1f", uncached / max(cached, 0.0001)))x")
        print("  (a 30fps frame budget is 33ms; this ran on the MAIN ACTOR)")
        print("──────────────────────────────────────────────────────────────────")
        print("")
        #expect(cached < uncached)
    }

    @Test("Measure the per-message chat-history disk write")
    func measureHistoryWrite() throws {
        // What `syncActive` used to do on EVERY message mutation: re-encode
        // every saved session and write the lot to disk, synchronously, on the
        // main actor.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ainkrad-histbench-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let persistence = FileDocumentStore(rootURL: root)
        let store = SageSessionStore(persistence: persistence)

        // 20 past chats of 40 messages each — an ordinary few weeks of use.
        for _ in 0..<20 {
            store.startNewSession()
            store.syncActive(
                messages: (0..<40).map { i in
                    AgentMessage(
                        role: i % 2 == 0 ? .user : .assistant,
                        content: [.text(String(repeating: "message body ", count: 40))])
                })
            store.flush()
        }

        let writes = 200  // a medium streamed reply
        let start = Date()
        for _ in 0..<writes { store.flush() }
        let elapsed = Date().timeIntervalSince(start)

        print("")
        print("── Chat history write, 20 sessions x 40 messages ──")
        print("  full encode + atomic write: \(String(format: "%.2f", elapsed / Double(writes) * 1000))ms each")
        print("  old cost for a \(writes)-chunk reply: \(String(format: "%.2f", elapsed))s of MAIN-ACTOR time")
        print("  new cost (coalesced at 600ms): ~1 write")
        print("───────────────────────────────────────────────────")
        print("")
        #expect(elapsed >= 0)
    }
}
