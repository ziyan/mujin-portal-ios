import Foundation

/// SpeechPiece is a piece of the answer asked to be read aloud.
public struct SpeechPiece: Equatable, Sendable {
    public let id: String
    public let text: String
}

/// VoiceAnswerSegmenter cuts an answer into pieces as it streams in. The
/// first piece is a single sentence so speech starts early; later ones are at
/// least `minimumLength` characters so the voice does not stutter. Code
/// blocks and the suggestions comment are skipped, and Markdown is stripped.
public struct VoiceAnswerSegmenter: Sendable {
    public static let minimumLength = 80
    /// The server takes at most 4,096 bytes a piece.
    public static let maximumBytes = 4_096

    private let idPrefix: String
    private var emittedCount = 0
    private var pieceCount = 0

    public init(idPrefix: String = "answer") { self.idPrefix = idPrefix }

    /// The pieces that became ready now that the answer reads `fullText`. At
    /// the end (`isFinal`) whatever is left is a piece, however short.
    public mutating func feed(_ fullText: String, isFinal: Bool) -> [SpeechPiece] {
        let speakable = Array(Self.speakableText(fullText))
        guard speakable.count > emittedCount else { return [] }
        var pieces: [SpeechPiece] = []
        var start = emittedCount
        while start < speakable.count {
            guard let end = nextCut(in: speakable, from: start, isFinal: isFinal) else { break }
            let text = String(speakable[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            start = end
            if !text.isEmpty {
                for part in Self.splitToFit(text) {
                    pieces.append(SpeechPiece(id: "\(idPrefix)-\(pieceCount)", text: part))
                    pieceCount += 1
                }
            }
        }
        emittedCount = start
        return pieces
    }

    /// Where the next piece ends, or nil when more text is needed first.
    private func nextCut(in characters: [Character], from start: Int, isFinal: Bool) -> Int? {
        let minimum = pieceCount == 0 ? 1 : Self.minimumLength
        var index = start
        while index < characters.count {
            if Self.endsSentence(characters, at: index, isFinal: isFinal), index + 1 - start >= minimum { return index + 1 }
            index += 1
        }
        return isFinal && start < characters.count ? characters.count : nil
    }

    /// Whether the sentence ends at `index`: a terminator followed by white space
    /// (or the end of a finished answer), or a line break after text.
    private static func endsSentence(_ characters: [Character], at index: Int, isFinal: Bool) -> Bool {
        let character = characters[index]
        if "。！？".contains(character) { return true }
        if character == "\n" { return true }
        guard ".!?".contains(character) else { return false }
        if index + 1 < characters.count { return characters[index + 1].isWhitespace }
        return isFinal
    }

    static func splitToFit(_ text: String) -> [String] {
        guard text.utf8.count > maximumBytes else { return [text] }
        var parts: [String] = []
        var current = ""
        for word in text.split(separator: " ", omittingEmptySubsequences: false) {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            if candidate.utf8.count > maximumBytes, !current.isEmpty {
                parts.append(current)
                current = String(word)
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    /// The text to read aloud: no fenced code, no suggestions comment, no
    /// Markdown marks. An unfinished fence or comment ends what is speakable.
    public static func speakableText(_ markdown: String) -> String {
        var text = markdown
        if let comment = text.range(of: "<!--suggestions:") { text = String(text[..<comment.lowerBound]) }
        var kept: [Substring] = []
        var isInFence = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                isInFence.toggle()
                continue
            }
            if !isInFence { kept.append(line) }
        }
        // An unfinished fence hides the rest of the answer.
        return kept.map { stripMarkdown(String($0)) }.joined(separator: "\n")
    }

    static func stripMarkdown(_ line: String) -> String {
        var text = line
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") { text = String(trimmed.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces) }
        else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") { text = String(trimmed.dropFirst(2)) }
        else if trimmed.hasPrefix("> ") { text = String(trimmed.dropFirst(2)) }
        // [label](address) reads as label.
        while let open = text.range(of: "["), let middle = text.range(of: "](", range: open.upperBound..<text.endIndex),
            let close = text.range(of: ")", range: middle.upperBound..<text.endIndex)
        {
            text.replaceSubrange(open.lowerBound..<close.upperBound, with: String(text[open.upperBound..<middle.lowerBound]))
        }
        for mark in ["**", "__", "`", "*", "~~"] { text = text.replacingOccurrences(of: mark, with: "") }
        return text
    }
}
