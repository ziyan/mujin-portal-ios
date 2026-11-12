import Foundation

/// RichMath finds the formulas in a message's words, the way the web does. What sits between `$…$`, `$$…$$`, `\(…\)` or `\[…\]` is a
/// formula only when it reads as one: it has a TeX command, an operator, a digit or a bracket, or it is a one- or two-letter name
/// such as `$x$`. Plain words stay words, so "$5 and $10" and "between $$ and $$" are text.
public enum RichMath {
    /// One stretch of a paragraph: words, or a formula with whether it stands on its own line.
    public enum Piece: Equatable, Sendable {
        case text(String)
        case formula(tex: String, isDisplay: Bool)
    }

    /// Whether what sits between delimiters is a formula rather than plain words.
    public static func isFormula(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == content || content.contains("\n") else { return false }
        if trimmed.range(of: #"\\[A-Za-z]+"#, options: .regularExpression) != nil { return true }
        if trimmed.range(of: #"^[A-Za-z]{1,2}$"#, options: .regularExpression) != nil { return true }
        if trimmed.contains(where: { $0.isNumber || "=+-*/^_<>(){}[]|".contains($0) }) {
            // Words with a number in them, as in an amount of money, are still words: a formula has no run of plain words.
            return trimmed.range(of: #"[A-Za-z]{3,}\s+[A-Za-z]{3,}"#, options: .regularExpression) == nil
        }
        return false
    }

    private static let delimiters: [(open: String, close: String, isDisplay: Bool)] = [
        ("$$", "$$", true), ("\\[", "\\]", true), ("\\(", "\\)", false), ("$", "$", false),
    ]

    /// A paragraph cut into words and formulas. Code in backticks is left as it is.
    public static func pieces(of text: String) -> [Piece] {
        var pieces: [Piece] = []
        var words = ""
        var index = text.startIndex
        var isInCode = false
        func flushWords() {
            if !words.isEmpty { pieces.append(.text(words)) }
            words = ""
        }
        while index < text.endIndex {
            let character = text[index]
            if character == "`" { isInCode.toggle() }
            if !isInCode, let found = formula(in: text, at: index) {
                flushWords()
                pieces.append(.formula(tex: found.tex, isDisplay: found.isDisplay))
                index = found.end
                continue
            }
            words.append(character)
            index = text.index(after: index)
        }
        flushWords()
        return pieces
    }

    private static func formula(in text: String, at index: String.Index) -> (tex: String, isDisplay: Bool, end: String.Index)? {
        for delimiter in delimiters where text[index...].hasPrefix(delimiter.open) {
            // A dollar right after a letter or digit, or an escaped one, opens nothing.
            if delimiter.open.hasPrefix("$"), index > text.startIndex {
                let before = text[text.index(before: index)]
                if before == "\\" || before.isLetter || before.isNumber || before == "$" { continue }
            }
            let start = text.index(index, offsetBy: delimiter.open.count)
            guard start < text.endIndex, let close = text[start...].range(of: delimiter.close) else { continue }
            let content = String(text[start..<close.lowerBound])
            if delimiter.open == "$", let after = text[close.upperBound...].first, after.isNumber { continue }
            guard isFormula(content) else { continue }
            return (content.trimmingCharacters(in: .whitespacesAndNewlines), delimiter.isDisplay, close.upperBound)
        }
        return nil
    }

    /// Whether a paragraph holds a formula, which is then drawn rather than shown as text.
    public static func hasFormula(_ text: String) -> Bool {
        pieces(of: text).contains { if case .formula = $0 { return true } else { return false } }
    }

    /// The paragraph as HTML for the drawing page: its words escaped with their bold, italic, code and links kept, and each formula
    /// in a span the page draws, holding its source as text.
    public static func html(of text: String) -> String {
        pieces(of: text).map { piece in
            switch piece {
            case .text(let words): inlineHTML(words)
            case .formula(let tex, let isDisplay): "<span class=\"tex\(isDisplay ? " display" : "")\">\(escaped(tex))</span>"
            }
        }.joined()
    }

    public static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Bold, italic, inline code and a link's words, as HTML; everything else as escaped text.
    static func inlineHTML(_ words: String) -> String {
        var html = escaped(words)
        let rules: [(String, String)] = [
            (#"`([^`]+)`"#, "<code>$1</code>"),
            (#"\*\*([^*]+)\*\*"#, "<strong>$1</strong>"),
            (#"(?<![\w*])\*([^*\s][^*]*)\*(?![\w*])"#, "<em>$1</em>"),
            (#"\[([^\]]+)\]\([^)\s]+\)"#, "$1"),
        ]
        for (pattern, template) in rules {
            html = html.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return html.replacingOccurrences(of: "\n", with: "<br>")
    }
}
