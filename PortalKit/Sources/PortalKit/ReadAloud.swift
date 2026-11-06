import Foundation

/// ReadAloudText is a message as it is said: the words, with nothing that only means something on a screen, cut into the pieces the
/// server speaks one request at a time. It follows the web app's spoken answers (`speakableText` and the segmenter that skips
/// code), so a message sounds the same on every screen.
public enum ReadAloudText {
    /// The server takes at most this many characters in one request.
    public static let maximumPieceCharacters = 4_096
    /// The first piece stays short so the first sound comes quickly; the later ones read a few sentences with their flow.
    public static let firstPieceCharacters = 200
    public static let followingPieceCharacters = 1_000

    /// What is said of a Markdown message. Code blocks, displayed formulas and HTML comments are left out whole, then images,
    /// bare addresses and inline formulas; a link says its words, the marks of headings, lists, quotes and emphasis go, and a
    /// table reads as its cells separated by commas.
    public static func speakable(from markdown: String) -> String {
        var text = droppingUnspokenBlocks(from: markdown)
        for rule in rules { text = rule.apply(to: text) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether anything of the message is said. A message of only code, or only an attachment, has nothing to read.
    public static func hasSpeakableText(_ markdown: String) -> Bool {
        speakable(from: markdown).contains { $0.isLetter || $0.isNumber }
    }

    /// The pieces to speak, in order, each of whole sentences and none longer than the server takes.
    public static func pieces(of markdown: String) -> [String] {
        split(speakable(from: markdown))
    }

    /// Cuts spoken text into pieces of whole sentences. A sentence longer than `maximumCharacters` is cut at a space.
    public static func split(
        _ text: String, firstCharacters: Int = firstPieceCharacters, followingCharacters: Int = followingPieceCharacters,
        maximumCharacters: Int = maximumPieceCharacters
    ) -> [String] {
        var pieces: [String] = []
        var current = ""
        for sentence in sentences(of: text).flatMap({ cut($0, toFit: maximumCharacters) }) {
            let limit = pieces.isEmpty ? firstCharacters : followingCharacters
            if current.isEmpty {
                current = sentence
            } else if current.count + 1 + sentence.count <= limit {
                current += " " + sentence
            } else {
                pieces.append(current)
                current = sentence
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    // MARK: sentences

    private static let terminators: Set<Character> = [".", "!", "?", ";", ":"]
    /// Full-width terminators end a sentence with no space after them, as that script is written.
    private static let wideTerminators: Set<Character> = ["。", "！", "？", "；"]
    private static let closers: Set<Character> = ["\"", "'", ")", "]"]

    static func sentences(of text: String) -> [String] {
        let characters = Array(text)
        var sentences: [String] = []
        var start = 0
        var index = 0
        while index < characters.count {
            let character = characters[index]
            var end: Int?
            if wideTerminators.contains(character) {
                end = index + 1
            } else if terminators.contains(character) {
                var next = index + 1
                while next < characters.count, closers.contains(characters[next]) { next += 1 }
                if next == characters.count || characters[next].isWhitespace { end = next }
            }
            if let end {
                append(String(characters[start..<end]), to: &sentences)
                start = end
                index = end
            } else {
                index += 1
            }
        }
        if start < characters.count { append(String(characters[start...]), to: &sentences) }
        return sentences
    }

    private static func append(_ sentence: String, to sentences: inout [String]) {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { sentences.append(trimmed) }
    }

    /// A sentence over the limit, cut at the last space that fits, or at the limit when it has none.
    static func cut(_ sentence: String, toFit maximumCharacters: Int) -> [String] {
        var remaining = Array(sentence)
        guard maximumCharacters > 0, remaining.count > maximumCharacters else { return [sentence] }
        var parts: [String] = []
        while remaining.count > maximumCharacters {
            let window = remaining[0..<maximumCharacters]
            let lastSpace = window.lastIndex(where: { $0.isWhitespace })
            let cutIndex = lastSpace.map { $0 > 0 ? $0 : maximumCharacters } ?? maximumCharacters
            append(String(remaining[0..<cutIndex]), to: &parts)
            remaining = Array(remaining[cutIndex...])
            while remaining.first?.isWhitespace == true { remaining.removeFirst() }
        }
        append(String(remaining), to: &parts)
        return parts
    }

    // MARK: what is dropped

    /// What is written for the screen and never said, as a pair of marks: a code block, a displayed formula and an HTML comment.
    private static let unspokenBlocks: [(opening: String, closing: String)] = [("```", "```"), ("\\[", "\\]"), ("$$", "$$"), ("<!--", "-->")]

    /// Drops each closed block whole, and what follows a block that is never closed.
    private static func droppingUnspokenBlocks(from markdown: String) -> String {
        var text = markdown
        var isDropped = true
        while isDropped {
            isDropped = false
            var readableEnd = text.endIndex
            for block in unspokenBlocks {
                guard let opened = text.range(of: block.opening) else { continue }
                if let closed = text.range(of: block.closing, range: opened.upperBound..<text.endIndex) {
                    text.replaceSubrange(opened.lowerBound..<closed.upperBound, with: "\n")
                    isDropped = true
                    break
                }
                if opened.lowerBound < readableEnd { readableEnd = opened.lowerBound }
            }
            if !isDropped { text = String(text[..<readableEnd]) }
        }
        return text
    }

    // MARK: the rules

    private struct Rule: @unchecked Sendable {
        let expression: NSRegularExpression
        let template: String

        init(_ pattern: String, _ template: String, isMultiline: Bool = false) {
            self.expression = try! NSRegularExpression(pattern: pattern, options: isMultiline ? [.anchorsMatchLines] : [])
            self.template = template
        }

        func apply(to text: String) -> String {
            expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
        }
    }

    /// The web app's `speakableText`, rule for rule and in its order.
    private static let rules: [Rule] = [
        Rule(#"!\[[^\]]*\]\([^)]*\)"#, ""),
        Rule(#"\[([^\]]+)\]\([^)]*\)"#, "$1"),
        Rule(#"<?https?:\/\/[^\s>)]*[^\s>).,!?;:]>?"#, ""),
        Rule("`([^`]*)`", "$1"),
        Rule(#"\\\(.+?\\\)"#, ""),
        Rule(#"^\s{0,3}#{1,6}\s+"#, "", isMultiline: true),
        Rule(#"^\s*>\s?"#, "", isMultiline: true),
        Rule(#"^\s*(?:[-*+]|\d+[.)])\s+"#, "", isMultiline: true),
        Rule(#"^\s*\|?\s*:?-{3,}.*$"#, "", isMultiline: true),
        Rule(#"\s*\|\s*"#, ", "),
        Rule(#"(\*\*|__|~~)(.+?)\1"#, "$2"),
        Rule(#"(^|[\s(])[*_]([^*_\n]+)[*_](?=[\s).,!?;:]|$)"#, "$1$2"),
        Rule(#"\s+"#, " "),
        Rule(#" ([.,!?;:])"#, "$1"),
        Rule(#"^[,\s]+|[,\s]+$"#, ""),
    ]
}
