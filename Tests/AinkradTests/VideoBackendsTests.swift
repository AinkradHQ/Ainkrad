import Testing
import Foundation
import AinkradHostRuntime
@testable import Ainkrad

@Suite("VideoBackends")
struct VideoBackendsTests {
    /// Routes by host: JSON for the API, raw bytes for the download CDN.
    private struct TwoHopHTTP: DataHTTPClient {
        let apiJSON: String; let videoBytes: [UInt8]; let apiHost: String
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let host = request.url?.host ?? ""
            let (body, _): (Data, Int) = host.contains(apiHost) ? (Data(apiJSON.utf8), 200) : (Data(videoBytes), 200)
            return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }
    private struct JSONHTTP: DataHTTPClient {
        let json: String; let status: Int
        init(json: String, status: Int = 200) { self.json = json; self.status = status }
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }
    private func keyed(_ id: String) -> InMemorySecretStore {
        let s = InMemorySecretStore(); s.setSecret("k", for: id); return s
    }
    private let mp4: [UInt8] = [0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70] // ftyp box

    // MARK: MediaFileExtension

    @Test func fileExtensionFromURL() {
        #expect(MediaFileExtension.forURL("https://cdn/x.webm", default: "mp4") == "webm")
        #expect(MediaFileExtension.forURL("https://cdn/x.mp4?token=1", default: "mp4") == "mp4")
        #expect(MediaFileExtension.forURL("https://cdn/noext", default: "mp4") == "mp4")
    }

    // MARK: Replicate video

    @Test func replicateNotConfigured() {
        #expect(ReplicateVideoBackend(secrets: InMemorySecretStore(), http: JSONHTTP(json: "{}")).isConfigured == false)
    }
    @Test func replicateSyncDownloadsVideo() async throws {
        let backend = ReplicateVideoBackend(
            secrets: keyed(ReplicateVideoBackend.secretID),
            http: TwoHopHTTP(apiJSON: #"{"output":"https://cdn.example/x.mp4"}"#, videoBytes: mp4, apiHost: "replicate.com"))
        let v = try await backend.generateVideo(prompt: "a wave")
        #expect(v.data == Data(mp4))
        #expect(v.fileExtension == "mp4")
    }

    // MARK: Luma parsing

    @Test func lumaParsing() throws {
        #expect(LumaVideoBackend.jobID(in: Data(#"{"id":"abc","state":"queued"}"#.utf8)) == "abc")
        #expect(try LumaVideoBackend.pollStatus(in: Data(#"{"state":"dreaming"}"#.utf8)) == .pending)
        #expect(try LumaVideoBackend.pollStatus(in: Data(#"{"state":"completed","assets":{"video":"https://cdn/v.mp4"}}"#.utf8)) == .done("https://cdn/v.mp4"))
        #expect(throws: ToolError.self) { try LumaVideoBackend.pollStatus(in: Data(#"{"state":"failed"}"#.utf8)) }
    }

    // MARK: fal parsing

    @Test func falParsing() throws {
        let urls = FalVideoBackend.queueURLs(in: Data(#"{"status_url":"https://q/s","response_url":"https://q/r"}"#.utf8))
        #expect(urls?.statusURL == "https://q/s")
        #expect(urls?.responseURL == "https://q/r")
        #expect(try FalVideoBackend.pollStatus(in: Data(#"{"status":"IN_PROGRESS"}"#.utf8)) == .pending)
        #expect(try FalVideoBackend.pollStatus(in: Data(#"{"status":"COMPLETED"}"#.utf8)) == .done("ready"))
        #expect(throws: ToolError.self) { try FalVideoBackend.pollStatus(in: Data(#"{"status":"FAILED"}"#.utf8)) }
        #expect(FalVideoBackend.videoURL(in: Data(#"{"video":{"url":"https://cdn/v.mp4"}}"#.utf8)) == "https://cdn/v.mp4")
        #expect(FalVideoBackend.videoURL(in: Data(#"{"url":"https://cdn/v2.mp4"}"#.utf8)) == "https://cdn/v2.mp4")
    }

    // MARK: Task 0.5 regression tests

    @Test func falEmptyStatusURLThrows() async {
        #expect(URL(string: "") == nil)
        let backend = FalVideoBackend(secrets: keyed(FalVideoBackend.secretID), http: JSONHTTP(json: #"{"status_url":"","response_url":""}"#))
        await #expect(throws: ToolError.self) {
            try await backend.generateVideo(prompt: "test")
        }
    }

    @Test func falInvalidVideoURLThrows() async {
        #expect(URL(string: "") == nil)
        let backend = FalVideoBackend(secrets: keyed(FalVideoBackend.secretID), http: JSONHTTP(json: #"{"status_url":"https://x/s","response_url":"https://x/r","status":"COMPLETED","url":""}"#))
        await #expect(throws: ToolError.self) {
            try await backend.generateVideo(prompt: "test")
        }
    }

    @Test func lumaInvalidVideoURLThrows() async {
        #expect(URL(string: "") == nil)
        let backend = LumaVideoBackend(secrets: keyed(LumaVideoBackend.secretID), http: JSONHTTP(json: #"{"id":"g1","state":"completed","assets":{"video":""}}"#))
        await #expect(throws: ToolError.self) {
            try await backend.generateVideo(prompt: "test")
        }
    }
}
