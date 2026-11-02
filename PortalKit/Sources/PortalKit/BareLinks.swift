import Foundation

/// BareLinks finds web addresses typed as plain text, which the system's
/// Markdown parsing leaves alone, so a message can make them links.
public enum BareLinks {
    /// One web address found in a text.
    public struct Match: Equatable, Sendable {
        public let range: Range<String.Index>
        public let url: URL
    }

    /// The `http` and `https` addresses in the text. A full stop, comma,
    /// colon, quotation mark or closing bracket at the end belongs to the
    /// sentence, not to the address, unless the bracket closes one inside it.
    /// Mail addresses and other schemes are not matched.
    public static func matches(in text: String) -> [Match] {
        var found: [Match] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex {
            guard let scheme = ["https://", "http://"]
                .compactMap({ text.range(of: $0, options: .caseInsensitive, range: searchStart..<text.endIndex) })
                .min(by: { $0.lowerBound < $1.lowerBound })
            else { break }
            searchStart = scheme.upperBound
            // `xhttps://` is a word, not an address.
            if scheme.lowerBound > text.startIndex, text[text.index(before: scheme.lowerBound)].isLetter || text[text.index(before: scheme.lowerBound)].isNumber {
                continue
            }
            var end = scheme.upperBound
            while end < text.endIndex, !isEnd(text[end]) { end = text.index(after: end) }
            while end > scheme.upperBound, shouldTrim(text[scheme.lowerBound..<end]) { end = text.index(before: end) }
            guard end > scheme.upperBound, let url = URL(string: String(text[scheme.lowerBound..<end])) else { continue }
            found.append(Match(range: scheme.lowerBound..<end, url: url))
            searchStart = end
        }
        return found
    }

    /// The text with each bare address a link, except where it is already a
    /// link or sits in a code span.
    public static func linked(_ text: AttributedString) -> AttributedString {
        var result = text
        let plain = String(text.characters)
        for match in matches(in: plain) {
            guard let start = AttributedString.Index(match.range.lowerBound, within: result), let end = AttributedString.Index(match.range.upperBound, within: result) else { continue }
            var isTaken = false
            for run in result[start..<end].runs {
                if run.link != nil { isTaken = true }
                if let intent = run.inlinePresentationIntent, intent.contains(InlinePresentationIntent.code) { isTaken = true }
            }
            if !isTaken { result[start..<end].link = match.url }
        }
        return result
    }

    /// The text as it is written, with its addresses as links.
    public static func linked(plainText text: String) -> AttributedString {
        linked(AttributedString(text))
    }

    private static func isEnd(_ character: Character) -> Bool {
        character.isWhitespace || character == "<" || character == ">" || character == "\"" || character == "\u{201D}"
    }

    private static func shouldTrim(_ address: Substring) -> Bool {
        guard let last = address.last else { return false }
        switch last {
        case ".", ",", ";", ":", "!", "?", "'", "*", "_", "\u{2019}":
            return true
        case ")":
            return address.filter { $0 == ")" }.count > address.filter { $0 == "(" }.count
        case "]":
            return address.filter { $0 == "]" }.count > address.filter { $0 == "[" }.count
        case "}":
            return address.filter { $0 == "}" }.count > address.filter { $0 == "{" }.count
        default:
            return false
        }
    }
}
