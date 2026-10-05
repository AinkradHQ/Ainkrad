import Foundation
import Testing

@testable import Ainkrad

@Suite("AgentToolPolicy")
struct AgentToolPolicyTests {
    @Test func allPolicyAllowsEverything() {
        let p = AgentToolPolicy.all
        #expect(p.allows(toolName: "edit_file", permission: .write))
        #expect(p.allows(toolName: "read_file", permission: .read))
    }

    @Test func restrictedReadOnlyDeniesWrites() {
        let p = AgentToolPolicy.restricted(allow: [], deny: [], allowClasses: [.read])
        #expect(p.allows(toolName: "read_file", permission: .read))
        #expect(!p.allows(toolName: "edit_file", permission: .write))
    }

    @Test func denyListWinsOverAllow() {
        let p = AgentToolPolicy.restricted(allow: ["git_op"], deny: ["git_op"], allowClasses: [.write])
        #expect(!p.allows(toolName: "git_op", permission: .write))
    }

    @Test func explicitAllowGrantsAToolOutsideItsClass() {
        let p = AgentToolPolicy.restricted(allow: ["run_terminal"], deny: [], allowClasses: [.read])
        #expect(p.allows(toolName: "run_terminal", permission: .write))
    }

    @Test func codableRoundTrips() throws {
        let p = AgentToolPolicy.restricted(allow: ["a"], deny: ["b"], allowClasses: [.read, .write])
        let data = try JSONEncoder().encode(p)
        #expect(try JSONDecoder().decode(AgentToolPolicy.self, from: data) == p)
    }

    @Test func memoryClassMapsCorrectlyAndIsNotMisclassifiedAsWrite() {
        let memoryAllowed = AgentToolPolicy.restricted(allow: [], deny: [], allowClasses: [.memory])
        #expect(memoryAllowed.allows(toolName: "memory_write", permission: .memory))

        let readOnly = AgentToolPolicy.restricted(allow: [], deny: [], allowClasses: [.read])
        #expect(!readOnly.allows(toolName: "memory_write", permission: .memory))
    }
}
