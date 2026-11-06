import Foundation

/// DictationPlace is where the words will go, which the server uses to tune what it listens for.
public enum DictationPlace: String, Sendable {
    /// The box of a conversation with the assistant.
    case agent
    /// The box of a chat between people.
    case chat
}

/// DictationFormat is the audio a dictation socket takes, as its `ready` event says.
public struct DictationFormat: Equatable, Sendable {
    public let sampleRateHertz: Int
    public let frameDurationMS: Int

    public init(sampleRateHertz: Int, frameDurationMS: Int) {
        self.sampleRateHertz = sampleRateHertz
        self.frameDurationMS = frameDurationMS
    }

    /// What a call uses: 24 kHz, 100 ms a frame.
    public static let standard = DictationFormat(sampleRateHertz: VoiceAudio.sampleRateHertz, frameDurationMS: VoiceAudio.frameDurationMS)

    /// 16-bit mono samples in one frame, as bytes. The server refuses a frame over 64 KiB.
    public var bytesPerFrame: Int { sampleRateHertz * frameDurationMS / 1_000 * VoiceAudio.bytesPerSample }

    /// The format the server named, or the standard one when it named nothing usable.
    public static func named(sampleRateHertz: Int, frameDurationMS: Int) -> DictationFormat {
        let named = DictationFormat(sampleRateHertz: sampleRateHertz, frameDurationMS: frameDurationMS)
        let isUsable = (8_000...48_000).contains(sampleRateHertz) && (20...1_000).contains(frameDurationMS)
            && named.bytesPerFrame > 0 && named.bytesPerFrame <= VoiceAudio.maximumFrameBytes
        return isUsable ? named : .standard
    }
}

/// DictationText puts what was heard into the message box.
public enum DictationText {
    /// The box with the heard words at its end, one space between them and what was there. Words that are only white space change
    /// nothing, and a box that already ends in white space gets no second one.
    public static func appending(_ heard: String, to existing: String) -> String {
        let words = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return existing }
        guard let last = existing.last else { return words }
        return last.isWhitespace ? existing + words : existing + " " + words
    }
}

/// DictationTiming is how long dictation waits.
public enum DictationTiming {
    /// Dictation stops by itself after this long with no words heard.
    public static let silenceLimitSeconds: TimeInterval = 30
    /// After the person taps stop, the longest the words still being said or transcribed are waited for.
    public static let finalWordsLimitSeconds: TimeInterval = 3
    /// After the person taps stop with nothing being said, how long the last final transcript is still waited for.
    public static let quietStopWaitSeconds: TimeInterval = 1

    /// How long to wait after stop before ending the session: `stop` ends it at once, so the last final transcript must land first.
    public static func stopWaitSeconds(isSpeechPending: Bool) -> TimeInterval {
        isSpeechPending ? finalWordsLimitSeconds : quietStopWaitSeconds
    }
}

/// DictationTracker follows what the dictation socket says: the live caption of each utterance, the final words of each once, which
/// utterances are still being transcribed, and how long it has been since any words were heard. It reads events the way the web app
/// does, so the same server behavior gives the same text on every screen.
public struct DictationTracker: Equatable, Sendable {
    /// What an event changed. A nil caption is no change; an empty one clears it.
    public struct Update: Equatable, Sendable {
        public var captionText: String?
        public var transcriptText: String?
        public var isNotHeard = false

        public init(captionText: String? = nil, transcriptText: String? = nil, isNotHeard: Bool = false) {
            self.captionText = captionText
            self.transcriptText = transcriptText
            self.isNotHeard = isNotHeard
        }
    }

    private var captions: [String: String] = [:]
    private var toldUtteranceIds: Set<String> = []
    private var currentUtteranceId = ""
    private var openUtteranceIds: Set<String> = []
    private var lastWordsAt: Date

    public init(startedAt: Date) { lastWordsAt = startedAt }

    /// Whether some speech was heard and its final words have not come yet.
    public var isSpeechPending: Bool { !openUtteranceIds.isEmpty }

    /// Whether no words have been heard for `limitSeconds`. Speech still being transcribed is not silence.
    public func isSilent(at date: Date, limitSeconds: TimeInterval = DictationTiming.silenceLimitSeconds) -> Bool {
        openUtteranceIds.isEmpty && date.timeIntervalSince(lastWordsAt) > limitSeconds
    }

    /// Reads one event of the socket, heard at `date`.
    public mutating func accept(_ event: VoiceServerEvent, at date: Date) -> Update {
        switch event {
        case .ready:
            lastWordsAt = date
            return Update()
        case .speechStarted(let utteranceId):
            lastWordsAt = date
            if !utteranceId.isEmpty { openUtteranceIds.insert(utteranceId) }
            currentUtteranceId = utteranceId
            if captions[utteranceId] == nil { captions[utteranceId] = "" }
            return Update(captionText: captions[utteranceId] ?? "")
        case .transcriptDelta(let utteranceId, let text):
            lastWordsAt = date
            guard !toldUtteranceIds.contains(utteranceId) else { return Update() }
            let captionText = (captions[utteranceId] ?? "") + text
            captions[utteranceId] = captionText
            return Update(captionText: captionText)
        case .transcriptFinal(let utteranceId, _, let text):
            lastWordsAt = date
            openUtteranceIds.remove(utteranceId)
            guard let captionText = finish(utteranceId) else { return Update() }
            let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return Update(captionText: captionText, transcriptText: words.isEmpty ? nil : words)
        case .transcriptFailed(let utteranceId, _, _):
            lastWordsAt = date
            openUtteranceIds.remove(utteranceId)
            guard let captionText = finish(utteranceId) else { return Update() }
            return Update(captionText: captionText, isNotHeard: true)
        default:
            return Update()
        }
    }

    /// Ends an utterance, once: the caption to show is then that of the utterance still being heard, if any.
    private mutating func finish(_ utteranceId: String) -> String? {
        guard !utteranceId.isEmpty, !toldUtteranceIds.contains(utteranceId) else { return nil }
        toldUtteranceIds.insert(utteranceId)
        captions[utteranceId] = nil
        return currentUtteranceId == utteranceId ? "" : (captions[currentUtteranceId] ?? "")
    }
}

/// VoiceAvailability is which of the voice features the server has set up for this person.
public struct VoiceAvailability: Decodable, Equatable, Sendable {
    public let isDictationAvailable: Bool
    public let isReadAloudAvailable: Bool

    public init(isDictationAvailable: Bool = false, isReadAloudAvailable: Bool = false) {
        self.isDictationAvailable = isDictationAvailable
        self.isReadAloudAvailable = isReadAloudAvailable
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isDictationAvailable = try container.decodeIfPresent(Bool.self, forKey: .isDictationAvailable) ?? false
        isReadAloudAvailable = try container.decodeIfPresent(Bool.self, forKey: .isReadAloudAvailable) ?? false
    }

    private enum CodingKeys: String, CodingKey { case isDictationAvailable, isReadAloudAvailable }

    /// Nothing is available: what a server that does not say gets.
    public static let unavailable = VoiceAvailability()
}

extension ServerCapabilities {
    /// Whether the voice setting says if dictation is set up. A server whose schema lacks the field refuses a query that names it.
    public var offersDictationAvailability: Bool { voiceSettingFieldNames.contains("isDictationAvailable") }
    public var offersReadAloudAvailability: Bool { voiceSettingFieldNames.contains("isReadAloudAvailable") }
}

extension Documents {
    /// The voice setting's availability, asking only for the fields the schema has.
    static func agentVoiceAvailability(isAskingForDictation: Bool, isAskingForReadAloud: Bool) -> String {
        var fields: [String] = []
        if isAskingForDictation { fields.append("isDictationAvailable") }
        if isAskingForReadAloud { fields.append("isReadAloudAvailable") }
        return "query GetAgentVoiceSetting { GetAgentVoiceSetting { \(fields.joined(separator: " ")) } }"
    }
}

extension Connection {
    /// Which voice features the server has for this person. The query is sent only when the schema has a field to ask for, and
    /// names only those fields; otherwise nothing is available and nothing is asked.
    public func voiceAvailability(capabilities: ServerCapabilities) async -> VoiceAvailability {
        let isAskingForDictation = capabilities.offersDictationAvailability
        let isAskingForReadAloud = capabilities.offersReadAloudAvailability
        guard isAskingForDictation || isAskingForReadAloud else { return .unavailable }
        struct Answer: Decodable, Sendable { let GetAgentVoiceSetting: VoiceAvailability }
        let document = Documents.agentVoiceAvailability(isAskingForDictation: isAskingForDictation, isAskingForReadAloud: isAskingForReadAloud)
        return (try? await execute(document, as: Answer.self).GetAgentVoiceSetting) ?? .unavailable
    }
}
