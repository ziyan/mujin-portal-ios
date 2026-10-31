import Foundation

/// VoicePlaybackQueue plays the pieces of an answer in the order they were
/// asked for, whatever order their audio arrives in, and forgets a piece that
/// was cancelled. It holds the audio of a later piece until the earlier ones
/// are done.
public struct VoicePlaybackQueue: Sendable {
    private struct Segment {
        let id: String
        var heldChunks: [Data] = []
        var releasedChunkCount = 0
        var isAudioDone = false
        var didFail = false
    }

    private var segments: [Segment] = []
    private var cancelled: Set<String> = []

    public init() {}

    /// Notes that a piece was asked for, in order.
    public mutating func asked(_ id: String) {
        guard !segments.contains(where: { $0.id == id }) else { return }
        segments.append(Segment(id: id))
    }

    /// The pieces asked for and not complete yet.
    public var openIds: [String] { segments.map(\.id) }

    /// A chunk of audio arrived. Returns what may play now, in order.
    public mutating func received(_ pcm: Data, for id: String) -> [Data] {
        guard !cancelled.contains(id), let index = segments.firstIndex(where: { $0.id == id }) else { return [] }
        segments[index].heldChunks.append(pcm)
        return release()
    }

    /// The piece's audio is complete.
    public mutating func audioDone(_ id: String) -> [Data] {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return [] }
        segments[index].isAudioDone = true
        return release()
    }

    /// The piece could not be spoken; the next piece goes on.
    public mutating func audioFailed(_ id: String) -> [Data] {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return [] }
        segments[index].isAudioDone = true
        segments[index].didFail = true
        return release()
    }

    /// Pieces the person talked over: their audio is ignored from now on.
    public mutating func cancel(_ ids: [String]) {
        cancelled.formUnion(ids)
        segments.removeAll { ids.contains($0.id) }
    }

    public mutating func cancelAll() -> [String] {
        let ids = segments.map(\.id)
        cancel(ids)
        return ids
    }

    /// Releases the chunks of the first piece, and of the next ones once it is done.
    private mutating func release() -> [Data] {
        var out: [Data] = []
        while !segments.isEmpty {
            out.append(contentsOf: segments[0].heldChunks)
            segments[0].releasedChunkCount += segments[0].heldChunks.count
            segments[0].heldChunks = []
            if segments[0].isAudioDone {
                segments.removeFirst()
            } else {
                break
            }
        }
        return out
    }
}

/// VoicePlaybackLedger remembers what was said aloud, so that when the
/// person talks over the answer the model is told what they heard.
public struct VoicePlaybackLedger: Sendable {
    public struct Piece: Equatable, Sendable {
        public let id: String
        public let text: String
        /// Samples played so far, and the total once the audio is complete.
        public var playedSampleCount = 0
        public var totalSampleCount: Int?
        public var isCancelled = false
    }

    public private(set) var pieces: [Piece] = []
    /// Characters a second, learned from complete pieces. A starting guess until one completes.
    private var charactersPerSecond = 15.0

    public init() {}

    public mutating func asked(id: String, text: String) { pieces.append(Piece(id: id, text: text)) }

    public mutating func played(id: String, sampleCount: Int) {
        guard let index = pieces.firstIndex(where: { $0.id == id }) else { return }
        pieces[index].playedSampleCount += sampleCount
    }

    public mutating func audioComplete(id: String, totalSampleCount: Int) {
        guard let index = pieces.firstIndex(where: { $0.id == id }), totalSampleCount > 0 else { return }
        pieces[index].totalSampleCount = totalSampleCount
        let seconds = Double(totalSampleCount) / Double(VoiceAudio.sampleRateHertz)
        if seconds > 0.5 { charactersPerSecond = Double(pieces[index].text.count) / seconds }
    }

    /// The part of a piece that was heard, cut to its last whole word. A
    /// finished piece is heard whole; a cut one only up to the words its audio reached.
    func heardText(of piece: Piece) -> String {
        if let total = piece.totalSampleCount, piece.playedSampleCount >= total { return piece.text }
        guard piece.playedSampleCount > 0 else { return "" }
        let seconds = Double(piece.playedSampleCount) / Double(VoiceAudio.sampleRateHertz)
        let count = min(piece.text.count, Int(seconds * charactersPerSecond))
        guard count > 0 else { return "" }
        if count >= piece.text.count { return piece.text }
        let cut = piece.text.index(piece.text.startIndex, offsetBy: count)
        // Only whole words count: a word the cut falls inside is not heard.
        if piece.text[cut].isWhitespace { return String(piece.text[..<cut]).trimmingCharacters(in: .whitespaces) }
        guard let space = piece.text[..<cut].lastIndex(where: \.isWhitespace) else { return "" }
        return String(piece.text[..<space]).trimmingCharacters(in: .whitespaces)
    }

    /// What the person heard, and what they did not: the answer spoken so far
    /// and the rest of it, which includes pieces never played and the part of
    /// the answer not yet cut into pieces.
    public func split(fullSpeakableText: String) -> (heard: String, unheard: String) {
        var heardParts: [String] = []
        for piece in pieces where !piece.isCancelled || piece.playedSampleCount > 0 {
            let heard = heardText(of: piece)
            if heard.isEmpty { break }
            heardParts.append(heard)
            if heard != piece.text { break }
        }
        let heard = heardParts.joined(separator: " ")
        let full = fullSpeakableText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heard.isEmpty else { return ("", full) }
        // The unheard part is what follows the heard words in the answer as it was written.
        if let range = Self.range(ofHeard: heard, in: full) {
            return (heard, String(full[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return (heard, "")
    }

    /// Finds the heard words at the start of the answer, ignoring differences in white space.
    private static func range(ofHeard heard: String, in full: String) -> Range<String.Index>? {
        var fullIndex = full.startIndex
        var heardIndex = heard.startIndex
        while heardIndex < heard.endIndex, fullIndex < full.endIndex {
            let heardCharacter = heard[heardIndex]
            let fullCharacter = full[fullIndex]
            if heardCharacter.isWhitespace && fullCharacter.isWhitespace {
                while heardIndex < heard.endIndex, heard[heardIndex].isWhitespace { heardIndex = heard.index(after: heardIndex) }
                while fullIndex < full.endIndex, full[fullIndex].isWhitespace { fullIndex = full.index(after: fullIndex) }
            } else if heardCharacter == fullCharacter {
                heardIndex = heard.index(after: heardIndex)
                fullIndex = full.index(after: fullIndex)
            } else {
                return nil
            }
        }
        return heardIndex == heard.endIndex ? full.startIndex..<fullIndex : nil
    }
}

/// InterruptionJudge tells the person talking over the answer from the
/// answer's own echo coming back into the microphone. With voice processing
/// most echo is already removed; what is left has a steady level, learned
/// while the answer plays and nobody is speaking.
public struct InterruptionJudge: Sendable {
    /// How far above the echo the microphone must be to be a person (a ratio).
    public static let personRatio: Float = 2.0
    /// A level below this is silence whatever the echo was.
    public static let floorLevel: Float = 0.02
    /// A transcript whose words are this much the same as what was just said is the echo.
    public static let echoWordShare = 0.7

    public private(set) var echoLevel: Float = 0

    public init() {}

    /// Learns the echo's level from a frame heard while the answer plays and
    /// the server has not reported speech.
    public mutating func learnEcho(frameLevel: Float) {
        echoLevel = echoLevel == 0 ? frameLevel : echoLevel * 0.9 + frameLevel * 0.1
    }

    public mutating func resetEcho() { echoLevel = 0 }

    /// Whether a frame this loud is more likely a person than the echo.
    public func isPerson(frameLevel: Float) -> Bool {
        frameLevel > max(Self.floorLevel, echoLevel * Self.personRatio)
    }

    /// Whether the words are the answer's own, heard again: most of them are
    /// in what was just played.
    public static func isEcho(transcript: String, justPlayed: String) -> Bool {
        let heard = words(transcript)
        guard heard.count >= 3 else { return false }
        let played = Set(words(justPlayed))
        let shared = heard.filter { played.contains($0) }.count
        return Double(shared) / Double(heard.count) >= echoWordShare
    }

    static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// The level (root mean square, 0 to 1) of 16-bit little-endian samples.
    public static func level(ofPCM pcm: Data) -> Float {
        let count = pcm.count / 2
        guard count > 0 else { return 0 }
        var sum: Double = 0
        pcm.withUnsafeBytes { raw in
            for index in 0..<count {
                let low = UInt16(raw[index * 2])
                let high = UInt16(raw[index * 2 + 1])
                let sample = Int16(bitPattern: low | (high << 8))
                let value = Double(sample) / 32_768
                sum += value * value
            }
        }
        return Float((sum / Double(count)).squareRoot())
    }
}
