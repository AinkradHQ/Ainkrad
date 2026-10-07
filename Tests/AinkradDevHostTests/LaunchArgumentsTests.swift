import Foundation
import Testing

@testable import AinkradDevHost

@Suite("LaunchArguments")
struct LaunchArgumentsTests {
    @Test("parses --bundle into bundleURL with nil generation")
    func parsesBundle() {
        let result = LaunchArguments.parse(["--bundle", "/x/My.bundle"])
        switch result {
        case .success(let args):
            #expect(args.bundleURL == URL(fileURLWithPath: "/x/My.bundle"))
            #expect(args.generation == nil)
        case .failure(let message):
            Issue.record("expected success, got failure: \(message)")
        }
    }

    @Test("parses --bundle and --generation")
    func parsesBundleAndGeneration() {
        let result = LaunchArguments.parse(["--bundle", "/x/My.bundle", "--generation", "3"])
        switch result {
        case .success(let args):
            #expect(args.bundleURL == URL(fileURLWithPath: "/x/My.bundle"))
            #expect(args.generation == 3)
        case .failure(let message):
            Issue.record("expected success, got failure: \(message)")
        }
    }

    @Test("missing --bundle yields a usage-message failure")
    func missingBundleFails() {
        let result = LaunchArguments.parse([])
        switch result {
        case .success:
            Issue.record("expected failure for missing --bundle")
        case .failure(let error):
            let message = String(describing: error)
            #expect(message.contains("usage:"))
            #expect(message.contains("--bundle"))
        }
    }

    @Test("non-integer --generation value yields a usage-message failure")
    func nonIntegerGenerationFails() {
        let result = LaunchArguments.parse(["--bundle", "/x/My.bundle", "--generation", "not-a-number"])
        switch result {
        case .success:
            Issue.record("expected failure for non-integer --generation")
        case .failure(let error):
            #expect(String(describing: error).contains("usage:"))
        }
    }
}
