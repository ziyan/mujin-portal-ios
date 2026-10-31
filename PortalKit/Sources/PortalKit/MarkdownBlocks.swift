import Foundation

/// MarkdownBlock is one block of an assistant answer. Inline styling (bold,
/// italic, code, links) is left to the screen, which renders each text with
/// the system's Markdown support.
public enum MarkdownBlock: Equatable, Sendable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case code(language: String, text: String)
    case bulletList([String])
    case numberedList([String])
    case quote(String)
    case rule
}

/// MarkdownBlocks splits Markdown into the blocks a screen lays out.
public enum MarkdownBlocks {
    public static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var numbers: [String] = []
        var quoteLines: [String] = []
        var codeLines: [String] = []
        var codeLanguage = ""
        var isInCode = false

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            if !bullets.isEmpty { blocks.append(.bulletList(bullets)) }
            if !numbers.isEmpty { blocks.append(.numberedList(numbers)) }
            if !quoteLines.isEmpty { blocks.append(.quote(quoteLines.joined(separator: "\n"))) }
            paragraph = []
            bullets = []
            numbers = []
            quoteLines = []
        }

        for line in markdown.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if isInCode {
                if trimmed.hasPrefix("```") {
                    blocks.append(.code(language: codeLanguage, text: codeLines.joined(separator: "\n")))
                    codeLines = []
                    isInCode = false
                } else {
                    codeLines.append(text)
                }
                continue
            }
            if trimmed.hasPrefix("```") {
                flush()
                codeLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                isInCode = true
            } else if trimmed.isEmpty {
                flush()
            } else if let heading = headingLevel(trimmed) {
                flush()
                blocks.append(.heading(level: heading, text: String(trimmed.dropFirst(heading + 1))))
            } else if ["---", "***", "___"].contains(trimmed) {
                flush()
                blocks.append(.rule)
            } else if let item = bulletItem(trimmed) {
                if !bullets.isEmpty || (paragraph.isEmpty && numbers.isEmpty && quoteLines.isEmpty) {
                    bullets.append(item)
                } else {
                    flush()
                    bullets.append(item)
                }
            } else if let item = numberedItem(trimmed) {
                if !numbers.isEmpty || (paragraph.isEmpty && bullets.isEmpty && quoteLines.isEmpty) {
                    numbers.append(item)
                } else {
                    flush()
                    numbers.append(item)
                }
            } else if trimmed.hasPrefix(">") {
                if quoteLines.isEmpty { flush() }
                quoteLines.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
            } else if !bullets.isEmpty, text.hasPrefix(" ") {
                // A wrapped line of the last bullet.
                bullets[bullets.count - 1] += " " + trimmed
            } else if !numbers.isEmpty, text.hasPrefix(" ") {
                numbers[numbers.count - 1] += " " + trimmed
            } else {
                if !bullets.isEmpty || !numbers.isEmpty || !quoteLines.isEmpty { flush() }
                paragraph.append(trimmed)
            }
        }
        if isInCode { blocks.append(.code(language: codeLanguage, text: codeLines.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    static func bulletItem(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(2))
        }
        return nil
    }

    static func numberedItem(_ line: String) -> String? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return String(rest.dropFirst(2))
    }
}
