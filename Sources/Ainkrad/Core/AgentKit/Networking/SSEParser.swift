import Foundation

/// Reassembles SSE `data:` events from a byte stream into event payload strings.
/// Emits one string per event (multi-line data joined by "\n"); terminates the
/// stream when a `[DONE]` sentinel is seen; ignores comments (`:`) and blanks.
enum SSEParser {
    static func events(from upstream: AsyncThrowingStream<Data, Error>) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { cont in
            let task = Task {
                var buffer = ""  // unterminated tail across chunks
                var dataLines: [String] = []
                func flush() -> Bool {  // returns false to signal [DONE]
                    guard !dataLines.isEmpty else { return true }
                    let payload = dataLines.joined(separator: "\n")
                    dataLines.removeAll()
                    if payload == "[DONE]" { return false }
                    cont.yield(payload)
                    return true
                }
                do {
                    for try await chunk in upstream {
                        buffer += String(decoding: chunk, as: UTF8.self)
                        while let nl = buffer.firstIndex(of: "\n") {
                            let raw = String(buffer[..<nl])
                            buffer = String(buffer[buffer.index(after: nl)...])
                            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
                            if line.isEmpty {  // event boundary
                                if !flush() {
                                    cont.finish()
                                    return
                                }
                            } else if line.hasPrefix(":") {  // comment / keep-alive
                                continue
                            } else if line.hasPrefix("data:") {
                                var v = String(line.dropFirst(5))
                                if v.hasPrefix(" ") { v.removeFirst() }
                                dataLines.append(v)
                            }
                            // non-data fields (event:, id:, retry:) ignored for this slice
                        }
                    }
                    _ = flush()
                    cont.finish()
                } catch { cont.finish(throwing: error) }
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }
}
