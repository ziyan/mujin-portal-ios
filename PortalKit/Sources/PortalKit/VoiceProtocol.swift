import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// VoiceAudio is the one audio format both directions of the voice socket use.
public enum VoiceAudio {
    public static let sampleRateHertz = 24_000
    /// One frame up is 100 ms: 2,400 samples of 16-bit mono, 4,800 bytes.
    public static let frameDurationMS = 100
    public static let samplesPerFrame = 2_400
    public static let bytesPerFrame = 4_800
    public static let bytesPerSample = 2
    /// A frame over 64 KiB, or with an odd byte count, is refused by the server.
    public static let maximumFrameBytes = 64 * 1_024

    /// How long a muted microphone keeps sending silence, so the server hears a pause end.
    public static let mutedSilenceSeconds: TimeInterval = 6
    /// How often a muted call says it is still there. A socket silent for 60 seconds is closed.
    public static let stillHereInterval: TimeInterval = 20
}

/// VoiceClientEvent is a text message to the voice socket.
public enum VoiceClientEvent: Equatable, Sendable {
    case hello(surface: String, speechVoice: String?)
    case speakAnswer(answerSegmentId: String, answerText: String)
    case cancelAnswer(answerSegmentIds: [String])
    case stillHere
    case stop

    public func encoded() -> String {
        var object: [String: JSONValue]
        switch self {
        case .hello(let surface, let speechVoice):
            object = ["voiceEvent": .string("hello"), "surface": .string(surface)]
            if let speechVoice, !speechVoice.isEmpty { object["speechVoice"] = .string(speechVoice) }
        case .speakAnswer(let id, let text):
            object = ["voiceEvent": .string("speakAnswer"), "answerSegmentId": .string(id), "answerText": .string(text)]
        case .cancelAnswer(let ids):
            object = ["voiceEvent": .string("cancelAnswer"), "answerSegmentIds": .array(ids.map { .string($0) })]
        case .stillHere: object = ["voiceEvent": .string("stillHere")]
        case .stop: object = ["voiceEvent": .string("stop")]
        }
        return String(decoding: (try? JSONEncoder().encode(JSONValue.object(object))) ?? Data(), as: UTF8.self)
    }
}

/// VoiceRefusalReason is why the server will not take a call, or ended one.
public enum VoiceRefusalReason: String, Sendable {
    /// The organization has no streaming transcription: use the older path.
    case notConfigured = "not_configured"
    case billing
    case providerRefused = "provider_refused"
    case providerUnreachable = "provider_unreachable"
    case badHello = "bad_hello"
    /// A call lasts 30 minutes at most; open a new one.
    case sessionTimeLimit = "session_time_limit"
}

/// VoiceServerEvent is a message from the voice socket.
public enum VoiceServerEvent: Equatable, Sendable {
    case ready(isSpeechAvailable: Bool, maximumSessionSeconds: Int, silenceTimeoutSeconds: Int)
    case refused(reason: String, message: String)
    case error(reason: String, message: String)
    case speechStarted(utteranceId: String)
    case speechStopped(utteranceId: String)
    case transcriptDelta(utteranceId: String, text: String)
    case transcriptFinal(utteranceId: String, sequence: Int, text: String)
    case transcriptFailed(utteranceId: String, sequence: Int, message: String)
    case problem(message: String)
    case answerAudio(answerSegmentId: String, pcm: Data)
    case answerAudioDone(answerSegmentId: String)
    case answerAudioFailed(answerSegmentId: String, message: String)

    public init?(decoding text: String) {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)), let name = value["voiceEvent"]?.stringValue else { return nil }
        func string(_ key: String) -> String { value[key]?.stringValue ?? "" }
        func number(_ key: String) -> Int { Int(value[key]?.numberValue ?? 0) }
        switch name {
        case "ready":
            self = .ready(
                isSpeechAvailable: value["isSpeechAvailable"]?.boolValue ?? false, maximumSessionSeconds: number("maximumSessionSeconds"),
                silenceTimeoutSeconds: number("silenceTimeoutSeconds"))
        case "refused": self = .refused(reason: string("refusalReason"), message: string("errorMessage"))
        case "error": self = .error(reason: string("refusalReason"), message: string("errorMessage"))
        case "speechStarted": self = .speechStarted(utteranceId: string("utteranceId"))
        case "speechStopped": self = .speechStopped(utteranceId: string("utteranceId"))
        case "transcriptDelta": self = .transcriptDelta(utteranceId: string("utteranceId"), text: string("transcriptText"))
        case "transcriptFinal":
            self = .transcriptFinal(utteranceId: string("utteranceId"), sequence: number("utteranceSequence"), text: string("transcriptText"))
        case "transcriptFailed":
            self = .transcriptFailed(utteranceId: string("utteranceId"), sequence: number("utteranceSequence"), message: string("errorMessage"))
        case "problem": self = .problem(message: string("errorMessage"))
        case "answerAudio":
            self = .answerAudio(answerSegmentId: string("answerSegmentId"), pcm: Data(base64Encoded: string("answerAudioBase64")) ?? Data())
        case "answerAudioDone": self = .answerAudioDone(answerSegmentId: string("answerSegmentId"))
        case "answerAudioFailed": self = .answerAudioFailed(answerSegmentId: string("answerSegmentId"), message: string("errorMessage"))
        default: return nil
        }
    }

    /// For a refusal or an error: the reason, when the app knows it.
    public var refusalReason: VoiceRefusalReason? {
        switch self {
        case .refused(let reason, _), .error(let reason, _): VoiceRefusalReason(rawValue: reason)
        default: nil
        }
    }
}

/// VoiceFrame is what a voice socket hands back.
public enum VoiceFrame: Equatable, Sendable {
    case text(String)
    case closed(code: Int?)
}

/// VoiceSocket is the WebSocket under a call: URLSession's in the app, a
/// scripted one in tests.
public protocol VoiceSocket: Sendable {
    func send(_ text: String) async throws
    /// One binary frame of microphone audio.
    func sendAudio(_ pcm: Data) async throws
    func receive() async throws -> VoiceFrame
    func close()
}

/// Opens a call's socket with the bearer token on the upgrade request.
public typealias VoiceSocketFactory = @Sendable (_ server: ServerAddress, _ accessToken: String) async throws -> any VoiceSocket

extension ServerAddress {
    /// The WebSocket address of the streaming voice socket.
    public var voiceEndpoint: URL {
        var components = URLComponents(url: endpoint("/api/v1/agent/voice"), resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "http" ? "ws" : "wss"
        return components.url!
    }
}

#if canImport(Darwin)
    /// URLSessionVoiceSocket is a voice socket on URLSession.
    public final class URLSessionVoiceSocket: VoiceSocket, @unchecked Sendable {
        private let task: URLSessionWebSocketTask

        init(task: URLSessionWebSocketTask) { self.task = task }

        public func send(_ text: String) async throws { try await task.send(.string(text)) }

        public func sendAudio(_ pcm: Data) async throws { try await task.send(.data(pcm)) }

        public func receive() async throws -> VoiceFrame {
            do {
                switch try await task.receive() {
                case .string(let text): return .text(text)
                case .data(let data): return .text(String(decoding: data, as: UTF8.self))
                @unknown default: return .text("")
                }
            } catch {
                let code = task.closeCode.rawValue
                return .closed(code: code > 0 ? code : nil)
            }
        }

        public func close() { task.cancel(with: .goingAway, reason: nil) }

        /// The real socket. An access token needs the `api:write` scope; the
        /// server answers 403 for `api:read` alone and 401 without a credential.
        public static let factory: VoiceSocketFactory = { server, accessToken in
            var request = URLRequest(url: server.voiceEndpoint)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let task = URLSession.shared.webSocketTask(with: request)
            task.resume()
            return URLSessionVoiceSocket(task: task)
        }
    }
#endif
