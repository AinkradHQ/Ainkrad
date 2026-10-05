import Foundation

/// A parsed markdown block. Inline formatting inside `paragraph`/`heading`/
/// list items is left as raw markdown source for the view layer to resolve
/// via `AttributedString(markdown:)`. Pure and unit-tested — no SwiftUI.
enum MarkdownBlock: Equatable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case bulletList([String])
    case orderedList([String])
    case codeBlock(language: String?, code: String)
    case thematicBreak
}

/// Lightweight, single-pass block splitter for assistant transcript text.
/// Cheap by design (line scan, no regex backtracking) so it can re-run on
/// every streaming update. An unterminated fence renders as an in-progress
/// code block rather than flickering back to plain text.
enum MarkdownBlocks {
    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = source.components(separatedBy: "\n")
        var i = 0
        var paragraph: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block.
            if trimmed.hasPrefix("```") {
                flushParagraph()
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                i += 1  // consume closing fence (or run off the end when unterminated)
                blocks.append(
                    .codeBlock(
                        language: lang.isEmpty ? nil : lang,
                        code: code.joined(separator: "\n")))
                continue
            }

            // Heading.
            if let h = heading(trimmed) {
                flushParagraph()
                blocks.append(h)
                i += 1
                continue
            }

            // Bullet list.
            if isBullet(trimmed) {
                flushParagraph()
                var items: [String] = []
                while i < lines.count, isBullet(lines[i].trimmingCharacters(in: .whitespaces)) {
                    items.append(bulletContent(lines[i].trimmingCharacters(in: .whitespaces)))
                    i += 1
                }
                blocks.append(.bulletList(items))
                continue
            }

            // Ordered list.
            if orderedContent(trimmed) != nil {
                flushParagraph()
                var items: [String] = []
                while i < lines.count, let c = orderedContent(lines[i].trimmingCharacters(in: .whitespaces)) {
                    items.append(c)
                    i += 1
                }
                blocks.append(.orderedList(items))
                continue
            }

            // Thematic break: 3+ of the SAME marker char ('-', '*', '_') and nothing else.
            if isThematicBreak(trimmed) {
                flushParagraph()
                blocks.append(.thematicBreak)
                i += 1
                continue
            }

            // Blank line ends a paragraph.
            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            paragraph.append(line)
            i += 1
        }
        flushParagraph()
        return blocks
    }

    private static func heading(_ line: String) -> MarkdownBlock? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix { $0 == "#" }
        let level = hashes.count
        guard level >= 1, level <= 6 else { return nil }
        let rest = line.dropFirst(level)
        guard rest.first == " " else { return nil }
        return .heading(level: level, text: rest.trimmingCharacters(in: .whitespaces))
    }

    private static func isBullet(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ")
    }

    private static func bulletContent(_ line: String) -> String {
        String(line.dropFirst(2))
    }

    private static func isThematicBreak(_ line: String) -> Bool {
        guard let first = line.first, "-*_".contains(first) else { return false }
        guard line.count >= 3, line.allSatisfy({ $0 == first }) else { return false }
        return true
    }

    private static func orderedContent(_ line: String) -> String? {
        // "<digits>. content"
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") else { return nil }
        return String(rest.dropFirst(2))
    }
}
