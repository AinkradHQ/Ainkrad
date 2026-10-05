// Tests/AinkradTests/ProviderPresetTests.swift
import Testing

@testable import Ainkrad

@Suite("ProviderPreset catalog")
struct ProviderPresetTests {
    @Test("every preset has a non-empty id and known kind")
    func catalogWellFormed() {
        for preset in ProviderPreset.all {
            #expect(!preset.id.isEmpty)
            #expect(!preset.displayName.isEmpty)
        }
        #expect(ProviderPreset.all.contains { $0.id == "openai" })
        #expect(ProviderPreset.all.contains { $0.id == "gemini" })
        #expect(ProviderPreset.all.contains { $0.id == "ollama" })
    }

    @Test("ollama requires no key; openai does")
    func keyRequirements() {
        #expect(ProviderPreset.preset(id: "ollama").requiresKey == false)
        #expect(ProviderPreset.preset(id: "openai").requiresKey == true)
    }

    @Test("kinds map correctly")
    func kinds() {
        #expect(ProviderPreset.preset(id: "claude").kind == .claude)
        #expect(ProviderPreset.preset(id: "gemini").kind == .gemini)
        #expect(ProviderPreset.preset(id: "openrouter").kind == .openAICompatible)
    }

    @Test("unknown id falls back to editable custom preset")
    func unknownFallsBackToCustom() {
        let p = ProviderPreset.preset(id: "does-not-exist")
        #expect(p.id == "custom")
        #expect(p.allowsBaseURLEdit == true)
    }
}
