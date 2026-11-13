import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// VoiceMessage is the audio a chat message carries: the attachment holding
/// the recording, how long it runs, the 48 bars drawn for it, and the words
/// the server heard in it.
public struct VoiceMessage: Codable, Equatable, Sendable {
    public let attachmentId: String?
    public let durationMS: Int?
    public let waveformLevels: [Int]?
    public let transcriptText: String?
    /// `waiting`, `done`, `failed` or `off`.
    public let transcriptState: String?

    public init(
        attachmentId: String? = nil, durationMS: Int? = nil, waveformLevels: [Int]? = nil, transcriptText: String? = nil, transcriptState: String? = nil
    ) {
        self.attachmentId = attachmentId
        self.durationMS = durationMS
        self.waveformLevels = waveformLevels
        self.transcriptText = transcriptText
        self.transcriptState = transcriptState
    }

    public var duration: TimeInterval { Double(durationMS ?? 0) / 1000 }

    /// The bars to draw: the server's levels, or a flat line for a message that has none.
    public var levels: [Int] {
        let given = waveformLevels ?? []
        return given.isEmpty ? Array(repeating: 24, count: VoiceMessageRules.waveformLevelCount) : given
    }

    /// What the "Show text" control reveals.
    public enum TranscriptStatus: Equatable, Sendable {
        case text(String)
        case waiting
        case failed
        /// No transcript was made, and none will be: transcription is off for the organization, or its cost was refused. Not a failure,
        /// and nothing is shown for it.
        case absent
    }

    public var transcriptStatus: TranscriptStatus {
        let words = (transcriptText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch transcriptState ?? "" {
        case "done": return words.isEmpty ? .failed : .text(words)
        case "failed": return .failed
        case "off": return .absent
        default: return words.isEmpty ? .waiting : .text(words)
        }
    }
}

/// VoiceMessageRules are the limits and the arithmetic of recording and playing a voice message.
public enum VoiceMessageRules {
    /// A recording shorter than this sends nothing.
    public static let minimumDuration: TimeInterval = 0.5
    /// A recording this long sends itself.
    public static let maximumDuration: TimeInterval = 120
    /// The countdown shows from here.
    public static let countdownStart: TimeInterval = 110
    public static let waveformLevelCount = 48
    public static let maximumLevel = 255
    /// How far up the finger slides to cancel, in points.
    public static let cancelDistance = 80.0
    public static let sampleRateHertz = 44_100.0
    public static let bitRate = 64_000

    public static func isTooShort(_ elapsed: TimeInterval) -> Bool { elapsed < minimumDuration }
    public static func isAtLimit(_ elapsed: TimeInterval) -> Bool { elapsed >= maximumDuration }

    /// The whole seconds left once the countdown has started, else nil.
    public static func countdownSecondsLeft(elapsed: TimeInterval) -> Int? {
        guard elapsed >= countdownStart else { return nil }
        return max(0, Int((maximumDuration - elapsed).rounded(.up)))
    }

    /// Whether a finger that moved `upward` points from where it went down is cancelling.
    public static func isCancelling(upward: Double) -> Bool { upward >= cancelDistance }

    /// A meter reading in decibels (about -160 to 0) as a height from 0 to 1. Anything under -50 is silence.
    public static func amplitude(decibels: Float) -> Float {
        guard decibels.isFinite else { return 0 }
        return max(0, min(1, (decibels + 50) / 50))
    }

    /// The 48 levels sent with a message, from readings of equal spacing in time: each bar is the loudest reading
    /// in its share of the recording, scaled so the loudest bar is at most 255. A quiet recording is not made to
    /// look loud: the scale never divides by less than 0.25.
    public static func levels(fromAmplitudes amplitudes: [Float], count: Int = waveformLevelCount) -> [Int] {
        guard count > 0 else { return [] }
        guard !amplitudes.isEmpty else { return Array(repeating: 0, count: count) }
        var bars: [Float] = []
        for index in 0..<count {
            let start = index * amplitudes.count / count
            let end = max(start + 1, (index + 1) * amplitudes.count / count)
            bars.append(amplitudes[start..<min(end, amplitudes.count)].max() ?? 0)
        }
        let scale = max(bars.max() ?? 0, 0.25)
        return bars.map { Int((min(1, $0 / scale) * Float(maximumLevel)).rounded()) }
    }

    /// Whether the levels are the ones the server accepts: 48 of them, each 0 to 255.
    public static func areValid(_ levels: [Int]) -> Bool {
        levels.count == waveformLevelCount && levels.allSatisfy { (0...maximumLevel).contains($0) }
    }

    /// `m:ss`, the way a player shows a time.
    public static func clockText(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// The time left in a message of `duration` that has played to `position`.
    public static func timeLeftText(duration: TimeInterval, position: TimeInterval) -> String {
        clockText(max(0, duration - position).rounded(.up))
    }

    /// How many of `count` bars are already played at `progress` (0 to 1).
    public static func playedBarCount(progress: Double, count: Int = waveformLevelCount) -> Int {
        Int((max(0, min(1, progress)) * Double(count)).rounded(.down))
    }

    /// The position a tap or drag at `fraction` (0 to 1) of the waveform's width seeks to.
    public static func seekPosition(fraction: Double, duration: TimeInterval) -> TimeInterval {
        max(0, min(1, fraction)) * duration
    }

    /// File types the phone's player cannot play: a browser's WebM recording.
    public static func canPlayOnPhone(contentType: String?, filename: String?) -> Bool {
        let type = (contentType ?? "").lowercased()
        let name = (filename ?? "").lowercased()
        if type.contains("webm") || name.hasSuffix(".webm") || type.contains("ogg") || name.hasSuffix(".ogg") { return false }
        return true
    }

    /// The name a recording is uploaded under.
    public static func filename(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "voice-\(formatter.string(from: date)).m4a"
    }

    public static let contentType = "audio/mp4"
}

/// PlayedVoiceMessages remembers which voice messages the person has played on this phone, so unplayed ones carry a dot.
public struct PlayedVoiceMessages: Codable, Equatable, Sendable {
    public static let capacity = 500

    public private(set) var messageIds: [String] = []

    public init(messageIds: [String] = []) { self.messageIds = messageIds }

    public func hasPlayed(_ messageId: String) -> Bool { messageIds.contains(messageId) }

    public mutating func markPlayed(_ messageId: String) {
        guard !hasPlayed(messageId) else { return }
        messageIds.append(messageId)
        if messageIds.count > Self.capacity { messageIds.removeFirst(messageIds.count - Self.capacity) }
    }
}

extension Documents {
    /// SendMessage with a voice message. The text is left out: the server refuses text with a voice message. The app uses this
    /// document only when the schema shows a `voiceMessage` argument.
    public static let sendChatVoiceMessage = """
        mutation SendMessage($conversationId: String!, $replyToMessageId: String, $surface: ConversationSurface, $voiceMessage: ConversationVoiceAudioInput) {
          SendMessage(conversationId: $conversationId, replyToMessageId: $replyToMessageId, surface: $surface, voiceMessage: $voiceMessage) {
            runId
            message { id role content createdAt \(chatMessageFields) }
          }
        }
        """
}

extension Connection {
    /// Sends a recording already uploaded as an attachment. The server checks that it is the person's own audio, and the bounds.
    public func sendChatVoiceMessage(
        conversationId: String, attachmentId: String, durationMS: Int, waveformLevels: [Int], replyToMessageId: String? = nil,
        isInternal: Bool = false
    ) async throws -> ConversationMessage? {
        struct Answer: Decodable, Sendable {
            struct Sent: Decodable, Sendable { let message: ConversationMessage? }
            let SendMessage: Sent
        }
        var variables: [String: JSONValue] = [
            "conversationId": .string(conversationId), "surface": .string("ios"),
            "voiceMessage": .object([
                "attachmentId": .string(attachmentId), "durationMS": .number(Double(durationMS)),
                "waveformLevels": .array(waveformLevels.map { .number(Double($0)) }),
            ]),
        ]
        if let replyToMessageId, !replyToMessageId.isEmpty { variables["replyToMessageId"] = .string(replyToMessageId) }
        var document = Documents.sendChatVoiceMessage
        if isInternal {
            // Only called with an internal note when the server has them, as a typed message is.
            document = Documents.withInternalArgument(document)
            variables["isInternal"] = .bool(true)
        }
        return try await execute(document, variables: variables, as: Answer.self).SendMessage.message
    }
}

extension Connection {
    /// The type the server stores an attachment as, from a HEAD request. Nil when it cannot be read.
    public func attachmentContentType(id: String) async -> String? {
        var request = URLRequest(url: account.server.endpoint("/api/v1/attachment/\(id)"))
        request.httpMethod = "HEAD"
        request.timeoutInterval = 15
        guard let (_, response) = try? await send(authorizing: request), (200..<300).contains(response.statusCode) else { return nil }
        return response.value(forHTTPHeaderField: "Content-Type")
    }
}
