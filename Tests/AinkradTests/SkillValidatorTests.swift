import Foundation
import Testing

@testable import Ainkrad

@Suite("SkillValidator")
struct SkillValidatorTests {
    private func skill(
        name: String = "ok-skill", body: String = "do things",
        desc: String = "does things"
    ) -> Skill {
        Skill(name: name, description: desc, body: body, allowedTools: [], triggers: [], source: .local)
    }

    @Test func acceptsWellFormedSkill() {
        #expect(SkillValidator.validate(skill()).isEmpty)
    }

    @Test func rejectsUnsafeNames() {
        #expect(!SkillValidator.isSafeName("../escape"))
        #expect(!SkillValidator.isSafeName("Has Spaces"))
        #expect(!SkillValidator.isSafeName("UPPER"))
        #expect(SkillValidator.isSafeName("pdf-processing"))
        #expect(SkillValidator.validate(skill(name: "../escape")).contains(.unsafeName("../escape")))
    }

    @Test func rejectsEmptyBody() {
        #expect(SkillValidator.validate(skill(body: "   ")).contains(.emptyBody))
    }

    @Test func rejectsEmptyDescription() {
        #expect(SkillValidator.validate(skill(desc: "")).contains(.emptyDescription))
    }
}
