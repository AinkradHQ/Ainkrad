import Foundation
import Testing

@testable import Ainkrad

@Suite("Setup you step")
@MainActor
struct SetupYouStepTests {
    @Test func profileFactsPersistAndReachTheAgentsMemory() throws {
        let t = TestHome.make("you")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        SetupYou.apply(
            values: [
                "name": "Ahmed", "callMe": "Ahmed", "role": "Engineer",
                "timezone": "Africa/Cairo",
            ],
            store: env.userProfileStore)

        #expect(env.userProfileStore.all()["name"] == "Ahmed")
        #expect(env.userProfileStore.all()["role"] == "Engineer")

        // The whole point of reusing this store: the assistant can read it.
        // `MemoryPaths(root: home.shared(.memory))` resolves `.user` to
        // `<memory root>/USER.md` — verified against MemoryFile.user's raw value.
        let userDoc = t.home.shared(.memory).appendingPathComponent("USER.md")
        #expect(FileManager.default.fileExists(atPath: userDoc.path))
        let body = try String(contentsOf: userDoc, encoding: .utf8)
        #expect(body.contains("Ahmed"))
    }

    @Test func blankFieldsAreNotWritten() {
        let t = TestHome.make("you2")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        SetupYou.apply(
            values: ["name": "Ahmed", "callMe": "", "role": "  ", "timezone": ""],
            store: env.userProfileStore)

        #expect(env.userProfileStore.all()["callMe"] == nil)
        #expect(env.userProfileStore.all()["role"] == nil)
    }

    /// Guards the fix for the review finding on `SetupYou.apply` and
    /// `SetupYouStepView.binding(for:)`: both are now driven directly off
    /// `UserProfileField.all` rather than a hardcoded key list, so a field
    /// renamed or added there is written through with no matching case to
    /// forget. This feeds `apply` a value for every key `UserProfileField.all`
    /// declares — exactly what the view's `values` dictionary does — and
    /// checks every one lands in the store.
    @Test func everyUserProfileFieldKeyIsWrittenThroughApply() {
        let t = TestHome.make("you3")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        let values = Dictionary(
            uniqueKeysWithValues:
                UserProfileField.all.map { ($0.key, "value-for-\($0.key)") })
        SetupYou.apply(values: values, store: env.userProfileStore)

        for field in UserProfileField.all {
            #expect(env.userProfileStore.all()[field.key] == "value-for-\(field.key)")
        }
    }
}
