import AinkradAppKitContract
import Testing

@testable import Ainkrad

/// The settings overlay rebuilds its catalog on every render, so a declared
/// row's typed-but-unsaved text has to live in `HostSettingsDrafts`. These pin
/// the regression class that rule exists for: text saved trimmed loses the
/// space between two words if the row reads the store instead of its draft.
@Suite("Host settings drafts")
@MainActor
struct HostSettingsDraftsTests {
    private let namePath = SettingsPath(["workspace", "you", "profile", "name"])

    private func textBinding(_ catalog: SettingsCatalog, _ path: SettingsPath) throws -> (
        get: String, set: (String) -> Void
    ) {
        let field = try #require(catalog.field(at: path))
        guard case .text(let binding) = field.kind else {
            Issue.record("\(path) is not a text row")
            return ("", { _ in })
        }
        return (binding.wrappedValue, { binding.wrappedValue = $0 })
    }

    @Test("a profile draft keeps its trailing space across a catalog rebuild, and the store gets it trimmed")
    func profileDraftSurvivesRebuild() throws {
        let environment = AppEnvironment.preview()
        try textBinding(HostSettingsCatalog.build(environment: environment), namePath).set("Ada ")

        #expect(environment.userProfileStore.all()["name"] == "Ada")
        let rebuilt = try textBinding(HostSettingsCatalog.build(environment: environment), namePath)
        #expect(rebuilt.get == "Ada ")

        rebuilt.set("Ada Lovelace")
        #expect(environment.userProfileStore.all()["name"] == "Ada Lovelace")
        #expect(try textBinding(HostSettingsCatalog.build(environment: environment), namePath).get == "Ada Lovelace")
    }

    @Test("emptying a profile row clears the stored fact")
    func emptyProfileRowClearsTheFact() throws {
        let environment = AppEnvironment.preview()
        let row = try textBinding(HostSettingsCatalog.build(environment: environment), namePath)
        row.set("Ada")
        row.set("   ")
        #expect(environment.userProfileStore.all()["name"] == nil)
    }

    @Test("a tool hook being composed keeps its interior spaces across a rebuild")
    func hookDraftSurvivesRebuild() throws {
        let environment = AppEnvironment.preview()
        let field = try #require(
            HostSettingsCatalog.build(environment: environment).allFields.first {
                $0.path.segments.last == "new-command"
            })
        try textBinding(HostSettingsCatalog.build(environment: environment), field.path).set("echo hello world ")

        #expect(environment.settingsDrafts.hookDraft.command == "echo hello world ")
        #expect(
            try textBinding(HostSettingsCatalog.build(environment: environment), field.path).get == "echo hello world ")
    }
}
