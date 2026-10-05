import AinkradAppKitContract
import Testing

@Suite("SettingsPath")
struct SettingsPathTests {
    @Test("round-trips through its raw dotted string")
    func roundTrips() throws {
        let path = SettingsPath(["assistant", "access", "permissions", "autoApproveReads"])
        #expect(path.rawValue == "assistant.access.permissions.autoApproveReads")
        #expect(SettingsPath(rawValue: path.rawValue) == path)
    }

    @Test("rejects empty and malformed raw values")
    func rejectsMalformed() {
        #expect(SettingsPath(rawValue: "") == nil)
        #expect(SettingsPath(rawValue: "a..b") == nil)
        #expect(SettingsPath(rawValue: ".leading") == nil)
        #expect(SettingsPath(rawValue: "trailing.") == nil)
    }

    @Test("appending extends the path and parent walks back up")
    func appendAndParent() throws {
        let group = SettingsPath(["workspace", "appearance", "theme"])
        let field = group.appending("accentColor")
        #expect(field.rawValue == "workspace.appearance.theme.accentColor")
        #expect(field.parent == group)
        #expect(SettingsPath(["workspace"]).parent == nil)
    }
}
