import Testing
import Foundation
@testable import Ainkrad

@Suite("ProviderManagement")
@MainActor
struct ProviderManagementTests {
    @Test func imagePresetsAreValidHTTPSEndpoints() {
        #expect(!HostSettingsCatalog.imagePresets.isEmpty)
        for p in HostSettingsCatalog.imagePresets {
            #expect(!p.label.isEmpty)
            #expect(p.url.hasPrefix("https://"))
        }
    }

    @Test func ttsPresetsAreValidHTTPSEndpoints() {
        #expect(!HostSettingsCatalog.speechPresets.isEmpty)
        for p in HostSettingsCatalog.speechPresets {
            #expect(!p.label.isEmpty)
            #expect(p.url.hasPrefix("https://"))
        }
    }
}
