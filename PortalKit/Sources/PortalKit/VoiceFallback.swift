import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// UtteranceSegmenter cuts a stream of 100 ms microphone frames into
/// utterances, for the older voice path that sends one recorded segment at a
/// time. An utterance starts when the level stays above the threshold for a
/// moment and ends after a pause.
public struct UtteranceSegmenter: Sendable {
    public enum Update: Equatable, Sendable {
        case nothing
        case speechStarted
        /// The utterance is over: its 16-bit PCM, with the lead-in kept.
        case utterance(Data)
    }

    public var startLevel: Float = 0.04
    /// Frames of speech in a row before an utterance starts.
    public var startFrameCount = 2
    /// Frames of silence in a row that end it.
    public var endFrameCount = 8
    /// Frames kept from before the start, so the first word is not clipped.
    public var leadInFrameCount = 3
    /// An utterance shorter than this many frames is noise.
    public var minimumFrameCount = 4

    private var leadIn: [Data] = []
    private var current: [Data] = []
    private var loudRun = 0
    private var quietRun = 0
    private var isInUtterance = false

    public init() {}

    public var isSpeaking: Bool { isInUtterance }

    public mutating func feed(frame: Data, level: Float) -> Update {
        if !isInUtterance {
            leadIn.append(frame)
            if leadIn.count > leadInFrameCount + startFrameCount { leadIn.removeFirst() }
            loudRun = level >= startLevel ? loudRun + 1 : 0
            guard loudRun >= startFrameCount else { return .nothing }
            isInUtterance = true
            current = leadIn
            leadIn = []
            quietRun = 0
            return .speechStarted
        }
        current.append(frame)
        quietRun = level >= startLevel ? 0 : quietRun + 1
        guard quietRun >= endFrameCount else { return .nothing }
        let frames = current
        isInUtterance = false
        current = []
        loudRun = 0
        quietRun = 0
        return frames.count - endFrameCount >= minimumFrameCount ? .utterance(frames.reduce(into: Data()) { $0.append($1) }) : .nothing
    }

    /// Drops what is held, such as when the call mutes.
    public mutating func reset() {
        leadIn = []
        current = []
        loudRun = 0
        quietRun = 0
        isInUtterance = false
    }
}

/// WAVFile wraps 16-bit mono PCM in the header a transcription service reads.
public enum WAVFile {
    public static func encode(pcm: Data, sampleRateHertz: Int = VoiceAudio.sampleRateHertz) -> Data {
        var header = Data()
        func append(_ text: String) { header.append(contentsOf: Array(text.utf8)) }
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) } }
        append("RIFF")
        append32(UInt32(36 + pcm.count))
        append("WAVE")
        append("fmt ")
        append32(16)
        append16(1)
        append16(1)
        append32(UInt32(sampleRateHertz))
        append32(UInt32(sampleRateHertz * 2))
        append16(2)
        append16(16)
        append("data")
        append32(UInt32(pcm.count))
        return header + pcm
    }
}

extension Documents {
    public static let getAgentVoiceSetting = """
        query GetAgentVoiceSetting { GetAgentVoiceSetting { speechVoice speechVoices defaultSpeechVoice previewText } }
        """

    public static let setAgentSpeechVoice = """
        mutation SetAgentSpeechVoice($speechVoice: String) {
          SetAgentSpeechVoice(speechVoice: $speechVoice) { speechVoice speechVoices defaultSpeechVoice previewText }
        }
        """

    static var voiceDocuments: [String] { [getAgentVoiceSetting, setAgentSpeechVoice] }
}

/// AgentVoiceSetting is which voice reads the assistant's answers.
public struct AgentVoiceSetting: Decodable, Equatable, Sendable {
    public let speechVoice: String?
    public let speechVoices: [String]?
    public let defaultSpeechVoice: String?
    public let previewText: String?

    /// The voice in use: the person's, else the default.
    public var effectiveVoice: String { (speechVoice ?? "").isEmpty ? (defaultSpeechVoice ?? "") : (speechVoice ?? "") }
}

extension Connection {
    public func voiceSetting() async throws -> AgentVoiceSetting {
        struct Answer: Decodable, Sendable { let GetAgentVoiceSetting: AgentVoiceSetting }
        return try await execute(Documents.getAgentVoiceSetting, as: Answer.self).GetAgentVoiceSetting
    }

    /// Chooses the voice; an empty name goes back to the default.
    public func setSpeechVoice(_ voice: String) async throws -> AgentVoiceSetting {
        struct Answer: Decodable, Sendable { let SetAgentSpeechVoice: AgentVoiceSetting }
        return try await execute(Documents.setAgentSpeechVoice, variables: ["speechVoice": .string(voice)], as: Answer.self).SetAgentSpeechVoice
    }

    /// The older voice path: one recorded utterance in, its text out
    /// (`POST /api/v1/voice/transcribe`). Used when the streaming socket says
    /// the organization has no streaming transcription.
    public func transcribe(wav: Data) async throws -> String {
        let boundary = "portal-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: account.server.endpoint("/api/v1/voice/transcribe"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await send(authorizing: request)
        guard response.statusCode == 200 else { throw Self.restRefusal(data, status: response.statusCode) }
        struct Answer: Decodable { let text: String? }
        return (try? JSONDecoder().decode(Answer.self, from: data))?.text ?? ""
    }

    /// The older voice path: text in, spoken audio out. The server parks the
    /// audio under a single-use token and the second request claims it.
    public func synthesize(text: String, voice: String?) async throws -> Data {
        var request = URLRequest(url: account.server.endpoint("/api/v1/voice/synthesize"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var fields: [String: JSONValue] = ["text": .string(text)]
        if let voice, !voice.isEmpty { fields["voice"] = .string(voice) }
        request.httpBody = try JSONEncoder().encode(JSONValue.object(fields))
        let (data, response) = try await send(authorizing: request)
        guard response.statusCode == 200 else { throw Self.speechRefusal(data, status: response.statusCode) }
        struct Token: Decodable { let token: String? }
        guard let token = (try? JSONDecoder().decode(Token.self, from: data))?.token, !token.isEmpty else { throw PortalError.unreadableAnswer }
        var components = URLComponents(url: account.server.endpoint("/api/v1/voice/stream"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        // The token is the credential here; nothing else is sent.
        let (audio, audioResponse) = try await transport.send(URLRequest(url: components.url!))
        guard audioResponse.statusCode == 200 else { throw Self.speechRefusal(audio, status: audioResponse.statusCode) }
        return audio
    }

    static func restRefusal(_ data: Data, status: Int) -> PortalError {
        .refused(restMessage(data) ?? "The server answered HTTP \(status).")
    }

    /// Why the server would not speak the text: its own reason when it gives one, else one for the status, such as a billing
    /// limit (402) or no speech provider set up (404).
    static func speechRefusal(_ data: Data, status: Int) -> PortalError {
        if let message = restMessage(data) { return .refused(message) }
        switch status {
        case 402, 403: return .refused("The limit for spoken messages has been reached.")
        case 404: return .refused("No speech provider is set up.")
        default: return .refused("The server answered HTTP \(status).")
        }
    }

    private static func restMessage(_ data: Data) -> String? {
        // The voice routes answer {"error": {"message": "..."}}; other routes a flat message or error string.
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        let message = value["error"]?["message"]?.stringValue ?? value["message"]?.stringValue ?? value["error"]?.stringValue
        guard let message, !message.isEmpty else { return nil }
        return message
    }
}
