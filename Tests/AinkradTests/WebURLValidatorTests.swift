import Foundation
import Testing

@testable import Ainkrad

@Suite("WebURLValidator")
struct WebURLValidatorTests {
    @Test func acceptsPublicHTTPS() throws {
        let url = try WebURLValidator.validate("https://example.com/page")
        #expect(url.host == "example.com")
    }
    @Test func rejectsNonHTTPScheme() {
        #expect(throws: ToolError.self) { _ = try WebURLValidator.validate("file:///etc/passwd") }
    }
    @Test func rejectsLoopback() {
        #expect(throws: ToolError.self) { _ = try WebURLValidator.validate("http://127.0.0.1/x") }
        #expect(throws: ToolError.self) { _ = try WebURLValidator.validate("http://localhost/x") }
    }
    @Test func rejectsPrivateRanges() {
        #expect(throws: ToolError.self) { _ = try WebURLValidator.validate("http://10.0.0.5") }
        #expect(throws: ToolError.self) { _ = try WebURLValidator.validate("http://192.168.1.1") }
        #expect(throws: ToolError.self) { _ = try WebURLValidator.validate("http://169.254.1.1") }
        #expect(throws: ToolError.self) { _ = try WebURLValidator.validate("http://[::1]") }
    }
    @Test func rejectsDecimalIntegerIP() {
        #expect(throws: ToolError.self) { _ = try WebURLValidator.validate("http://2130706433/") }  // 127.0.0.1
        #expect(throws: ToolError.self) { _ = try WebURLValidator.validate("http://2852039166/") }  // 169.254.169.254 (metadata)
    }
    @Test func rejectsTrailingDotBypass() {
        // FQDN root dot: the resolver treats these as the bare literal — must still be blocked.
        #expect(throws: ToolError.self) { _ = try WebURLValidator.validate("http://169.254.169.254./latest") }  // metadata
        #expect(throws: ToolError.self) { _ = try WebURLValidator.validate("http://127.0.0.1./x") }
        #expect(throws: ToolError.self) { _ = try WebURLValidator.validate("http://192.168.1.1./") }
        #expect(throws: ToolError.self) { _ = try WebURLValidator.validate("http://localhost./x") }
    }
    @Test func stillAllowsFQDNWithRootDot() throws {
        let url = try WebURLValidator.validate("https://example.com./page")  // legit FQDN root dot
        #expect(url.host == "example.com.")  // original URL preserved; only the check is normalized
    }
    @Test func rejectsHexAndOctalIP() {
        #expect(throws: ToolError.self) { _ = try WebURLValidator.validate("http://0x7f000001/") }  // 127.0.0.1 hex
        #expect(throws: ToolError.self) { _ = try WebURLValidator.validate("http://0177.0.0.1/") }  // 127.0.0.1 octal
    }
    @Test func rejectsShorthandIP() {
        #expect(throws: ToolError.self) { _ = try WebURLValidator.validate("http://127.1/") }  // shorthand 127.0.0.1
        #expect(throws: ToolError.self) { _ = try WebURLValidator.validate("http://10.1/") }  // shorthand 10.0.0.1
    }
    @Test func rejectsIPv4MappedIPv6() {
        #expect(throws: ToolError.self) { _ = try WebURLValidator.validate("http://[::ffff:127.0.0.1]/") }
        #expect(throws: ToolError.self) { _ = try WebURLValidator.validate("http://[::ffff:169.254.169.254]/") }
    }
    @Test func stillAllowsPublicIPv4() throws {
        let url = try WebURLValidator.validate("http://93.184.216.34/")  // public (example.com)
        #expect(url.host == "93.184.216.34")
    }
}
