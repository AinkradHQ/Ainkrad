import AinkradHostRuntime
import Testing

@testable import Ainkrad
@testable import AinkradAppKit

struct PluginValidatorTests {
    private func meta(id: String = "hello", api: Int = 1) -> PluginBundleMetadata {
        PluginBundleMetadata(
            appID: id, displayName: "Hello", iconSymbol: "hand.wave",
            apiVersion: api, principalClassName: "HelloEntryPoint")
    }

    private func info(_ exe: String? = "MyPlugin") -> [String: Any] {
        var d: [String: Any] = [:]
        if let exe { d["CFBundleExecutable"] = exe }
        return d
    }

    @Test("valid app ids pass, unsafe ones fail")
    func appID() {
        #expect(PluginValidator.isValidAppID("hello.world_1-2"))
        #expect(!PluginValidator.isValidAppID(""))
        #expect(!PluginValidator.isValidAppID("."))
        #expect(!PluginValidator.isValidAppID(".."))
        #expect(!PluginValidator.isValidAppID("../evil"))
        #expect(!PluginValidator.isValidAppID("a/b"))
    }

    @Test("valid metadata within API range passes")
    func metadataOK() {
        if case .success = PluginValidator.validate(meta(), infoDictionary: info(), minSupportedAPIVersion: 1) {
        } else {
            Issue.record("expected success")
        }
    }

    @Test("unsupported API version is rejected")
    func metadataBadAPI() {
        let r = PluginValidator.validate(meta(api: 999), infoDictionary: info(), minSupportedAPIVersion: 1)
        if case .failure(let rej) = r { #expect(rej.reason.contains("999")) } else { Issue.record("expected failure") }
    }

    @Test("invalid app id is rejected")
    func metadataBadID() {
        let r = PluginValidator.validate(meta(id: "../x"), infoDictionary: info(), minSupportedAPIVersion: 1)
        if case .failure(let rej) = r {
            #expect(rej.reason == "invalid app id")
        } else {
            Issue.record("expected failure")
        }
    }

    @Test("a bundle missing CFBundleExecutable is rejected")
    func missingExecutable() {
        let r = PluginValidator.validate(meta(), infoDictionary: info(nil), minSupportedAPIVersion: 1)
        if case .failure(let rej) = r {
            #expect(rej.reason == "missing CFBundleExecutable")
        } else {
            Issue.record("expected failure")
        }
    }

    @Test("an empty CFBundleExecutable is rejected")
    func emptyExecutable() {
        let r = PluginValidator.validate(meta(), infoDictionary: info(""), minSupportedAPIVersion: 1)
        if case .failure(let rej) = r {
            #expect(rej.reason == "missing CFBundleExecutable")
        } else {
            Issue.record("expected failure")
        }
    }
}

@Suite struct PluginValidatorRangeTests {
    private func meta(api: Int) -> PluginBundleMetadata {
        PluginBundleMetadata(
            appID: "sample", displayName: "S", iconSymbol: "star",
            apiVersion: api, principalClassName: "P")
    }
    private let info: [String: Any] = ["CFBundleExecutable": "Sample"]

    @Test func belowMinIsRejectedWithRangeMessage() {
        let r = PluginValidator.validate(
            meta(api: 5), infoDictionary: info,
            minSupportedAPIVersion: GenerationSupport.minSupported)
        guard case .failure(let rej) = r else {
            Issue.record("expected failure")
            return
        }
        #expect(rej.reason.contains("\(GenerationSupport.minSupported)"))
        #expect(rej.reason.contains("\(GenerationSupport.current)"))
    }
    @Test func inRangeSucceeds() {
        let r = PluginValidator.validate(
            meta(api: GenerationSupport.current), infoDictionary: info,
            minSupportedAPIVersion: GenerationSupport.minSupported)
        #expect((try? r.get()) != nil)
    }
}
