import Foundation
import Testing

@testable import Ainkrad

@Suite("Skill catalog model")
struct SkillCatalogModelTests {
    @Test func decodesLegacyPluginEntryAsPluginKind() throws {
        let json = """
            {"appID":"x","displayName":"X","icon":"app","description":"d","version":"1.0",
             "apiVersion":4,"downloadURL":"https://e/x.zip","sha256":"abc","sourceRepo":"o/r"}
            """.data(using: .utf8)!
        let entry = try JSONDecoder().decode(CatalogEntry.self, from: json)
        #expect(entry.kind == .plugin)
        #expect(entry.skill == nil)
    }

    @Test func decodesSkillEntry() throws {
        let json = """
            {"appID":"pdf-processing","displayName":"PDF Processing","icon":"doc",
             "description":"work with PDFs","version":"1.0","apiVersion":0,
             "downloadURL":"https://e/none","sha256":"","sourceRepo":"o/r","kind":"skill",
             "skill":{"contentURL":"https://e/pdf/SKILL.md"}}
            """.data(using: .utf8)!
        let entry = try JSONDecoder().decode(CatalogEntry.self, from: json)
        #expect(entry.kind == .skill)
        #expect(entry.skill?.contentURL.absoluteString == "https://e/pdf/SKILL.md")
        #expect(entry.isValidSkillEntry)
    }

    @Test func invalidSkillEntryWithoutDescriptor() throws {
        let json = """
            {"appID":"broken","displayName":"B","icon":"i","description":"d","version":"1",
             "apiVersion":0,"downloadURL":"https://e/n","sha256":"","sourceRepo":"o/r","kind":"skill"}
            """.data(using: .utf8)!
        let entry = try JSONDecoder().decode(CatalogEntry.self, from: json)
        #expect(!entry.isValidSkillEntry)
    }
}
