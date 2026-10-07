import Testing

@testable import Ainkrad

@Suite("SessionShareRenderer")
struct SessionShareRendererTests {
    @Test func selfContainedWithInlineImageAndRedaction() {
        let messages = [
            AgentMessage(role: .user, content: [.text("token sk-live-XYZ here")]),
            AgentMessage(
                role: .assistant,
                content: [
                    .thinking("secret reasoning"),
                    .text("done"),
                    .image(mediaType: "image/png", base64: "AAAA"),
                ]),
        ]
        let html = SessionShareRenderer.render(messages, title: "My Session", redactions: ["sk-live-XYZ"])
        #expect(html.hasPrefix("<!doctype html>"))
        #expect(html.contains("My Session"))
        #expect(html.contains("[redacted]"))
        #expect(!html.contains("sk-live-XYZ"))
        #expect(html.contains("data:image/png;base64,AAAA"))  // image inlined, self-contained
        #expect(!html.contains("secret reasoning"))  // thinking omitted
        #expect(!html.contains("<link"))  // no external stylesheet
        #expect(html.contains("<style>"))  // CSS inlined
    }

    @Test func titleIsRedactedNotJustEscaped() {
        // Task 4 derives the title from the first user message, so a secret typed
        // as the first message must not leak into <title>/<h1>.
        let html = SessionShareRenderer.render(
            [AgentMessage(role: .user, text: "x")],
            title: "leak sk-live-XYZ", redactions: ["sk-live-XYZ"])
        #expect(!html.contains("sk-live-XYZ"))
        #expect(html.contains("[redacted]"))
    }

    @Test func mediaTypeQuotesAreEscapedNoAttributeBreakout() {
        // A crafted mediaType containing a double quote must not break out of the
        // double-quoted src attribute.
        let html = SessionShareRenderer.render(
            [
                AgentMessage(
                    role: .assistant,
                    content: [
                        .image(mediaType: "image/png\" onerror=\"alert(1)", base64: "AAAA")
                    ])
            ],
            title: "T", redactions: [])
        #expect(!html.contains("onerror=\"alert(1)"))  // no raw breakout
        #expect(html.contains("&quot;"))  // quote escaped instead
    }

    @Test func toolResultContentIsRedacted() {
        let html = SessionShareRenderer.render(
            [
                AgentMessage(
                    role: .assistant,
                    content: [
                        .toolResult(toolUseID: "0", content: "leaked sk-live-XYZ", isError: false)
                    ])
            ],
            title: "T", redactions: ["sk-live-XYZ"])
        #expect(!html.contains("sk-live-XYZ"))
    }
}
