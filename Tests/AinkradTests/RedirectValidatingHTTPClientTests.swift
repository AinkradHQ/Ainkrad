import Foundation
import Testing

@testable import Ainkrad

@Suite("RedirectValidatingHTTPClient")
struct RedirectValidatingHTTPClientTests {
    @Test func followsPublicHTTPS() {
        #expect(RedirectValidatingHTTPClient.isSafeRedirectTarget(URL(string: "https://www.example.com/x")!))
    }
    @Test func refusesPrivateAndLoopback() {
        #expect(!RedirectValidatingHTTPClient.isSafeRedirectTarget(URL(string: "http://169.254.169.254/latest")!))
        #expect(!RedirectValidatingHTTPClient.isSafeRedirectTarget(URL(string: "http://127.0.0.1/x")!))
        #expect(!RedirectValidatingHTTPClient.isSafeRedirectTarget(URL(string: "http://10.0.0.5/x")!))
    }
    @Test func refusesNonHTTPScheme() {
        #expect(!RedirectValidatingHTTPClient.isSafeRedirectTarget(URL(string: "file:///etc/passwd")!))
    }
}
