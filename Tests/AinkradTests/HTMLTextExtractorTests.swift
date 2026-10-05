import Testing

@testable import Ainkrad

@Suite("HTMLTextExtractor")
struct HTMLTextExtractorTests {
    @Test func stripsTagsAndScripts() {
        let html =
            "<html><head><style>.a{color:red}</style></head>"
            + "<body><h1>Hi</h1><script>evil()</script><p>World &amp; peace</p></body></html>"
        let text = HTMLTextExtractor.plainText(from: html)
        #expect(text.contains("Hi"))
        #expect(text.contains("World & peace"))
        #expect(!text.contains("evil"))
        #expect(!text.contains("color:red"))
    }
    @Test func collapsesWhitespace() {
        #expect(HTMLTextExtractor.plainText(from: "<p>a</p>\n\n\n<p>b</p>").contains("a"))
    }
}
