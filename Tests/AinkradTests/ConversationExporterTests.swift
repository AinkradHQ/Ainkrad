import Foundation
import Testing

@testable import Ainkrad

@Suite("ConversationExporter")
struct ConversationExporterTests {
    private let convo: [AgentMessage] = [
        AgentMessage(role: .user, text: "hello with secret sk-123"),
        AgentMessage(role: .assistant, text: "hi <there>"),
    ]

    @Test func markdownRoundTrip() {
        let md = ConversationExporter.export(convo, format: .markdown)
        #expect(md.contains("**User**"))
        #expect(md.contains("**Sage**"))
        #expect(md.contains("hello"))
    }

    @Test func htmlEscapes() {
        let html = ConversationExporter.export(convo, format: .html)
        #expect(html.contains("&lt;there&gt;"))
        #expect(html.contains("<html"))
    }

    @Test func redactionRemovesSecret() {
        let md = ConversationExporter.export(convo, format: .markdown, redactions: ["sk-123"])
        #expect(!md.contains("sk-123"))
        #expect(md.contains("[redacted]"))
    }
}
