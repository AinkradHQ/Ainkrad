import AinkradAppKitContract
import Testing

@testable import Ainkrad

@Suite("User profile settings")
@MainActor
struct UserProfileSettingsTests {
    /// These four keys are the wizard's, verbatim
    /// (SetupYouStepView.swift:139-154). A rename on either side must fail
    /// here rather than silently orphaning the facts already on disk.
    @Test("the field list matches the wizard's keys exactly")
    func keysMatchWizard() {
        #expect(UserProfileField.all.map(\.key) == ["name", "callMe", "role", "timezone"])
    }

    @Test("every field has a title and a hint")
    func copyIsPresent() {
        for field in UserProfileField.all {
            #expect(!field.title.isEmpty)
            #expect(!field.hint.isEmpty)
        }
    }

    @Test("the You page is registered in the host catalog")
    func pageRegistered() {
        let catalog = HostSettingsCatalog.build(environment: .preview())
        #expect(catalog.pages.contains { $0.path == SettingsPath(["workspace", "you"]) })
    }
}
