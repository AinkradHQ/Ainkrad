import Darwin
import Foundation

/// Validates a URL at the trust boundary before any network fetch. Refuses
/// non-http(s) schemes and host literals that resolve to loopback/private/
/// link-local space (SSRF guard). NOTE: this checks the host LITERAL only —
/// DNS-rebinding of a public name is a known residual risk; the read-class
/// approval gate is the backstop. Re-run on the final redirect URL.
enum WebURLValidator {
    static func validate(_ raw: String) throws -> URL {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
            let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else {
            throw ToolError.message("web_fetch only allows http(s) URLs.")
        }
        guard var host = url.host?.lowercased(), !host.isEmpty else {
            throw ToolError.message("web_fetch requires a URL with a host.")
        }
        // Normalize a single trailing "." (the FQDN root dot). The system
        // resolver treats `169.254.169.254.` / `localhost.` as the bare literal,
        // but `inet_aton` and the string checks below would otherwise miss the
        // dotted form — a confirmed SSRF bypass. Strip it before every check.
        if host.hasSuffix(".") { host.removeLast() }
        if host == "localhost" || host.hasSuffix(".local") {
            throw ToolError.message("web_fetch refuses local hostnames.")
        }
        if isPrivateOrLoopback(host) {
            throw ToolError.message("web_fetch refuses private/loopback addresses.")
        }
        return url
    }

    /// True if the host literal resolves to loopback / private / link-local /
    /// unique-local / metadata space. Uses `inet_aton` (which decodes dotted,
    /// decimal-integer, octal `0…`, hex `0x…`, and shorthand IPv4 forms — the
    /// classic SSRF-bypass encodings) and `inet_pton` for IPv6 (incl. the
    /// IPv4-mapped `::ffff:a.b.c.d` form). A non-IP host (a real DNS name)
    /// returns false and is allowed — DNS-rebinding of a public NAME is the
    /// documented residual risk backed by the redirect-revalidating client.
    private static func isPrivateOrLoopback(_ host: String) -> Bool {
        let h = host.hasPrefix("[") ? String(host.dropFirst().dropLast()) : host
        if h.contains(":") {  // IPv6 literal
            var addr = in6_addr()
            guard inet_pton(AF_INET6, h, &addr) == 1 else { return false }
            let b = withUnsafeBytes(of: &addr) { Array($0) }  // 16 bytes
            if b.allSatisfy({ $0 == 0 }) { return true }  // ::  unspecified
            if b[0...14].allSatisfy({ $0 == 0 }) && b[15] == 1 { return true }  // ::1 loopback
            if b[0] == 0xfe && (b[1] & 0xc0) == 0x80 { return true }  // fe80::/10 link-local
            if (b[0] & 0xfe) == 0xfc { return true }  // fc00::/7 ULA
            // IPv4-mapped ::ffff:a.b.c.d  and IPv4-compatible ::a.b.c.d
            if b[0...9].allSatisfy({ $0 == 0 })
                && ((b[10] == 0xff && b[11] == 0xff) || (b[10] == 0 && b[11] == 0))
            {
                return isPrivateIPv4(a: Int(b[12]), b: Int(b[13]), c: Int(b[14]), d: Int(b[15]))
            }
            return false
        }
        var addr = in_addr()  // IPv4 (any encoding inet_aton accepts)
        guard inet_aton(h, &addr) == 1 else { return false }
        let ip = UInt32(bigEndian: addr.s_addr)
        return isPrivateIPv4(
            a: Int((ip >> 24) & 0xff), b: Int((ip >> 16) & 0xff),
            c: Int((ip >> 8) & 0xff), d: Int(ip & 0xff))
    }

    private static func isPrivateIPv4(a: Int, b: Int, c: Int, d: Int) -> Bool {
        if a == 0 || a == 10 || a == 127 { return true }
        if a == 169 && b == 254 { return true }  // link-local / metadata
        if a == 192 && b == 168 { return true }  // private
        if a == 172 && (16...31).contains(b) { return true }  // private
        if a == 100 && (64...127).contains(b) { return true }  // CGNAT (RFC 6598)
        return false
    }
}
