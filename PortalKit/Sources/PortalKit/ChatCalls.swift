import Foundation

/// ChatCallMember is one person a call rang or holds.
public struct ChatCallMember: Codable, Equatable, Identifiable, Sendable {
    public let userId: String
    public let userName: String?
    /// `none` (the starter), `ringing`, `answered`, `declined` or `missed`.
    public let ringState: String?
    public let isInCall: Bool?
    public let isMuted: Bool?
    public let isVideoOn: Bool?
    public var id: String { userId }

    public init(
        userId: String, userName: String? = nil, ringState: String? = nil, isInCall: Bool? = nil, isMuted: Bool? = nil, isVideoOn: Bool? = nil
    ) {
        self.userId = userId
        self.userName = userName
        self.ringState = ringState
        self.isInCall = isInCall
        self.isMuted = isMuted
        self.isVideoOn = isVideoOn
    }

    public var shownName: String { (userName ?? "").isEmpty ? "Someone" : userName! }
    public var isOnCall: Bool { isInCall == true }
    public var isRinging: Bool { ringState == "ringing" && !isOnCall }
}

/// ChatCallSegment is a stretch of the call's transcript: who spoke, what, and when in the call.
public struct ChatCallSegment: Codable, Equatable, Sendable {
    public let id: String?
    public let userId: String?
    public let userName: String?
    public let text: String?
    public let startMS: Int?
    public let endMS: Int?

    public init(id: String? = nil, userId: String? = nil, userName: String? = nil, text: String? = nil, startMS: Int? = nil, endMS: Int? = nil) {
        self.id = id
        self.userId = userId
        self.userName = userName
        self.text = text
        self.startMS = startMS
        self.endMS = endMS
    }
}

/// ChatCallRecording is one person's audio from a call that was recorded.
public struct ChatCallRecording: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let filename: String?
    public let uploadedByUserId: String?

    public init(id: String, filename: String? = nil, uploadedByUserId: String? = nil) {
        self.id = id
        self.filename = filename
        self.uploadedByUserId = uploadedByUserId
    }
}

/// ChatCallTranscriptStatus is what a call that is over can say about its recording and transcript.
public enum ChatCallTranscriptStatus: Equatable, Sendable {
    case none
    case transcribing
    case ready
    case failed
}

/// ChatCall is a call in a chat, going or over, as the call screen, the banner and the line in the chat know it.
public struct ChatCall: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let chatId: String?
    public let startedByUserId: String?
    public let startedByUserName: String?
    public let chatDisplayName: String?
    public let startedAt: String?
    public let endedAt: String?
    /// `ended`, `missed`, `declined` or `failed`; empty while the call is going.
    public let endReason: String?
    public let durationMS: Int?
    public let isTranscriptionOn: Bool?
    public let transcriptionTurnedOnByUserId: String?
    public let transcriptionTurnedOnByName: String?
    /// `off`, `recording`, `waiting`, `done` or `failed`.
    public let transcriptState: String?
    public let members: [ChatCallMember]?
    /// What was said. A call read from a chat's history leaves this out, so `GetChatCall` is asked when it is opened.
    public let transcriptSegments: [ChatCallSegment]?
    /// Each person's audio, from `GetChatCall` only.
    public let recordingAttachments: [ChatCallRecording]?

    public init(
        id: String, chatId: String? = nil, startedByUserId: String? = nil, startedByUserName: String? = nil, chatDisplayName: String? = nil,
        startedAt: String? = nil, endedAt: String? = nil, endReason: String? = nil, durationMS: Int? = nil, isTranscriptionOn: Bool? = nil,
        transcriptionTurnedOnByUserId: String? = nil, transcriptionTurnedOnByName: String? = nil, transcriptState: String? = nil,
        members: [ChatCallMember]? = nil, transcriptSegments: [ChatCallSegment]? = nil, recordingAttachments: [ChatCallRecording]? = nil
    ) {
        self.id = id
        self.chatId = chatId
        self.startedByUserId = startedByUserId
        self.startedByUserName = startedByUserName
        self.chatDisplayName = chatDisplayName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.endReason = endReason
        self.durationMS = durationMS
        self.isTranscriptionOn = isTranscriptionOn
        self.transcriptionTurnedOnByUserId = transcriptionTurnedOnByUserId
        self.transcriptionTurnedOnByName = transcriptionTurnedOnByName
        self.transcriptState = transcriptState
        self.members = members
        self.transcriptSegments = transcriptSegments
        self.recordingAttachments = recordingAttachments
    }

    /// A call is going while it has no end.
    public var isGoing: Bool { (endedAt ?? "").isEmpty }
    public var startDate: Date? { PortalDate.parse(startedAt) }
    public var allMembers: [ChatCallMember] { members ?? [] }
    public var joinedMembers: [ChatCallMember] { allMembers.filter(\.isOnCall) }

    public func member(_ userId: String?) -> ChatCallMember? { allMembers.first { $0.userId == userId } }

    /// The members who could be rung now: in the chat, not on the call and not ringing.
    public func membersToRing(among chatMembers: [ChatMember], excluding userId: String) -> [ChatMember] {
        let onCallOrRinging = Set(allMembers.filter { $0.isOnCall || $0.isRinging }.map(\.userId))
        return chatMembers.filter { $0.isPresent && $0.userId != userId && !onCallOrRinging.contains($0.userId) }
    }

    /// Whether this person is being rung and has not answered.
    public func isRinging(userId: String) -> Bool {
        isGoing && (member(userId)?.isRinging ?? false)
    }

    /// How long the call ran: the server's figure, else from its two stamps.
    public var duration: TimeInterval? {
        if let durationMS, durationMS > 0 { return Double(durationMS) / 1000 }
        if let start = startDate, let end = PortalDate.parse(endedAt) { return max(0, end.timeIntervalSince(start)) }
        return nil
    }

    public var transcriptStatus: ChatCallTranscriptStatus {
        guard !isGoing else { return .none }
        switch transcriptState {
        case "done": return .ready
        case "waiting", "recording": return .transcribing
        case "failed": return .failed
        default: return .none
        }
    }

    public func spokenSegments() -> [ChatCallSegment] {
        (transcriptSegments ?? []).filter { !($0.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

/// ChatCallRules are the numbers and wording of a call.
public enum ChatCallRules {
    /// A call holds at most this many people at once.
    public static let maximumParticipants = 16
    /// Nobody answering within this long makes the call missed.
    public static let ringTimeout: TimeInterval = 60

    /// `m:ss`, or `h:mm:ss` past an hour.
    public static func elapsedText(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded(.down)))
        if whole >= 3600 { return String(format: "%d:%02d:%02d", whole / 3600, (whole % 3600) / 60, whole % 60) }
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    public static func elapsedText(since start: Date?, now: Date = Date()) -> String {
        elapsedText(start.map { now.timeIntervalSince($0) } ?? 0)
    }

    /// The line of an ended call: its length, or Missed or Declined.
    public enum LineOutcome: Equatable, Sendable {
        case going
        case ended(duration: TimeInterval?)
        case missed
        case declined
        case failed
    }

    public static func outcome(of call: ChatCall) -> LineOutcome {
        guard !call.isGoing else { return .going }
        switch call.endReason ?? "" {
        case "missed": return .missed
        case "declined": return .declined
        case "failed": return .failed
        default: return .ended(duration: call.duration)
        }
    }

    /// Whether the person can start a call from this chat: it has someone else in it.
    public static func canStart(in room: ChatRoom?, userId: String) -> Bool {
        guard let room, room.canWrite else { return false }
        return room.currentMembers.contains { $0.userId != userId }
    }
}

/// ChatCallEvent is one change the account's call feed reports. It carries the call as the server holds it afterwards.
public struct ChatCallEvent: Codable, Equatable, Sendable {
    /// `started`, `ringing`, `stop_ringing`, `joined`, `left`, `declined`, `ended`, `media_changed`, `transcription_turned_on` or `transcript_ready`.
    public let eventType: String
    public let callId: String?
    public let chatId: String?
    public let actorUserId: String?
    public let actorUserName: String?
    public let ringedUserIds: [String]?
    public let call: ChatCall?

    public init(
        eventType: String, callId: String? = nil, chatId: String? = nil, actorUserId: String? = nil, actorUserName: String? = nil,
        ringedUserIds: [String]? = nil, call: ChatCall? = nil
    ) {
        self.ringedUserIds = ringedUserIds
        self.eventType = eventType
        self.callId = callId
        self.chatId = chatId
        self.actorUserId = actorUserId
        self.actorUserName = actorUserName
        self.call = call
    }

    public var resolvedCallId: String? { call?.id ?? callId }
}

/// ChatCallSignal is the server's offer to renegotiate the media of a call the person is in.
public struct ChatCallSignal: Codable, Equatable, Sendable {
    public let callId: String?
    /// `offer` or `closed`.
    public let signalKind: String?
    public let offerSdp: String?
    public let sequenceNumber: Int?

    public init(callId: String? = nil, signalKind: String? = nil, offerSdp: String? = nil, sequenceNumber: Int? = nil) {
        self.callId = callId
        self.signalKind = signalKind
        self.offerSdp = offerSdp
        self.sequenceNumber = sequenceNumber
    }
}

/// What the screens must do after an event the book cannot settle itself.
public enum ChatCallEffect: Equatable, Sendable {
    case none
    /// This person is being rung for a call.
    case ringing(ChatCall)
    /// A call this person was rung for is over, or was answered on another device.
    case stopped(callId: String)
    /// The event named a call without describing it: read it.
    case refetch(callId: String)
}

/// ChatCallBook is the going calls of the person's chats, kept current by the account's call feed.
public struct ChatCallBook: Equatable, Sendable {
    public private(set) var goingCalls: [String: ChatCall] = [:]

    public init() {}

    public mutating func replaceAll(_ calls: [ChatCall]) {
        goingCalls = Dictionary(calls.filter(\.isGoing).map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    /// The going call of a chat, if there is one.
    public func goingCall(inChat chatId: String?) -> ChatCall? {
        guard let chatId else { return nil }
        return goingCalls.values.first { $0.chatId == chatId }
    }

    @discardableResult
    public mutating func apply(_ event: ChatCallEvent, userId: String) -> ChatCallEffect {
        if event.eventType == "stop_ringing", let callId = event.resolvedCallId {
            if let call = event.call, call.isGoing { goingCalls[call.id] = call }
            return .stopped(callId: callId)
        }
        guard let call = event.call else {
            guard let callId = event.callId, !callId.isEmpty else { return .none }
            return .refetch(callId: callId)
        }
        let wasRinging = goingCalls[call.id]?.isRinging(userId: userId) ?? false
        if call.isGoing {
            goingCalls[call.id] = call
            if call.isRinging(userId: userId), !wasRinging { return .ringing(call) }
            if wasRinging, !call.isRinging(userId: userId) { return .stopped(callId: call.id) }
            return .none
        }
        goingCalls[call.id] = nil
        return wasRinging || call.member(userId)?.ringState == "ringing" ? .stopped(callId: call.id) : .none
    }
}

/// CallSignalQueue hands the server's offers to a handler one at a time, in the order they came, and holds them
/// until the person's own join has finished: an offer made before the join would answer a connection that does not exist yet.
public actor CallSignalQueue {
    public typealias Handler = @Sendable (ChatCallSignal) async -> Void

    private var pending: [ChatCallSignal] = []
    private var isJoined = false
    private var isDraining = false
    private let handle: Handler

    public init(handle: @escaping Handler) { self.handle = handle }

    public var pendingCount: Int { pending.count }

    public func receive(_ signal: ChatCallSignal) async {
        pending.append(signal)
        await drain()
    }

    /// The join is done: the offers that waited are handled now.
    public func joinCompleted() async {
        isJoined = true
        await drain()
    }

    public func reset() {
        pending = []
        isJoined = false
    }

    private func drain() async {
        guard !isDraining else { return }
        isDraining = true
        while isJoined, !pending.isEmpty {
            let next = pending.removeFirst()
            await handle(next)
        }
        isDraining = false
    }
}

extension Documents {
    static let callFields = """
        id chatId chatDisplayName startedByUserId startedByUserName startedAt endedAt endReason durationMS isTranscriptionOn
        transcriptionTurnedOnByUserId transcriptionTurnedOnByName transcriptState
        members { userId userName ringState isInCall isMuted isVideoOn }
        transcriptSegments { id userId userName text startMS endMS }
        """

    /// What a chat message adds when the server has voice messages and calls. Sent only to a server that offers them.
    static let chatVoiceFields = "voiceMessage { attachmentId durationMS waveformLevels transcriptText transcriptState }"
    static let chatCallLineFields = "call { \(callFields) }"

    /// A document with the voice and call fields added wherever it asks for a chat message's fields.
    public static func withChatMedia(_ document: String, hasVoice: Bool = true, hasCalls: Bool = true) -> String {
        let fields = [hasVoice ? chatVoiceFields : nil, hasCalls ? chatCallLineFields : nil].compactMap { $0 }.joined(separator: " ")
        guard !fields.isEmpty else { return document }
        return document.replacingOccurrences(of: "linkPreviewsRemovedAt", with: "linkPreviewsRemovedAt \(fields)")
    }

    public static let isChatCallAvailable = "query IsChatCallAvailable { IsChatCallAvailable }"

    public static let listGoingChatCalls = "query ListGoingChatCalls { ListGoingChatCalls { \(callFields) } }"

    public static let getChatCall = "query GetChatCall($callId: String) { GetChatCall(callId: $callId) { \(callFields) recordingAttachments { id filename uploadedByUserId } } }"

    public static let startChatCall = """
        mutation StartChatCall($chatId: String, $userIds: [String], $isVideoOn: Boolean) {
          StartChatCall(chatId: $chatId, userIds: $userIds, isVideoOn: $isVideoOn) { call { \(callFields) } isExistingCall }
        }
        """

    public static let joinChatCall = "mutation JoinChatCall($callId: String, $pushDeviceId: String) { JoinChatCall(callId: $callId, pushDeviceId: $pushDeviceId) { call { \(callFields) } } }"

    public static let declineChatCall = "mutation DeclineChatCall($callId: String, $pushDeviceId: String) { DeclineChatCall(callId: $callId, pushDeviceId: $pushDeviceId) { call { id } } }"

    public static let leaveChatCall = "mutation LeaveChatCall($callId: String) { LeaveChatCall(callId: $callId) { call { id } } }"

    public static let ringChatCallMembers = """
        mutation RingChatCallMembers($callId: String, $userIds: [String]) { RingChatCallMembers(callId: $callId, userIds: $userIds) { call { \(callFields) } } }
        """

    public static let setChatCallMedia = """
        mutation SetChatCallMedia($callId: String, $isMuted: Boolean, $isVideoOn: Boolean) {
          SetChatCallMedia(callId: $callId, isMuted: $isMuted, isVideoOn: $isVideoOn) { call { \(callFields) } }
        }
        """

    public static let setChatCallTranscription = """
        mutation SetChatCallTranscription($callId: String, $isTranscriptionOn: Boolean) {
          SetChatCallTranscription(callId: $callId, isTranscriptionOn: $isTranscriptionOn) { call { \(callFields) } }
        }
        """

    public static let joinChatCallMedia = """
        mutation JoinChatCallMedia($callId: String, $offerSdp: String) { JoinChatCallMedia(callId: $callId, offerSdp: $offerSdp) { answerSdp } }
        """

    public static let answerChatCallMedia = """
        mutation AnswerChatCallMedia($callId: String, $answerSdp: String) { AnswerChatCallMedia(callId: $callId, answerSdp: $answerSdp) }
        """

    public static let getChatCallMaximumPersonCount = "query GetChatCallMaximumPersonCount { GetChatCallMaximumPersonCount }"

    public static let setChatCallVideoSubscriptions = """
        mutation SetChatCallVideoSubscriptions($callId: String!, $subscriptions: [ChatCallVideoSubscriptionInput!]!) {
          SetChatCallVideoSubscriptions(callId: $callId, subscriptions: $subscriptions)
        }
        """

    public static let onChatCallEvent = """
        subscription OnChatCallEvent {
          OnChatCallEvent { eventType callId chatId actorUserId actorUserName ringedUserIds call { \(callFields) } }
        }
        """

    public static let onChatCallSignal = """
        subscription OnChatCallSignal($callId: String!) { OnChatCallSignal(callId: $callId) { callId signalKind offerSdp sequenceNumber } }
        """

    /// The call operations, checked against the schema once the server has them.
    static var chatCallDocuments: [String] {
        [
            isChatCallAvailable, listGoingChatCalls, getChatCall, startChatCall, joinChatCall, declineChatCall, leaveChatCall, ringChatCallMembers,
            setChatCallMedia, setChatCallTranscription, joinChatCallMedia, answerChatCallMedia, onChatCallEvent, onChatCallSignal,
            getChatCallMaximumPersonCount, setChatCallVideoSubscriptions,
        ]
    }

    /// The voice message operation, checked against the schema once the server has it.
    static var chatVoiceMessageDocuments: [String] { [sendChatVoiceMessage] }
}

extension ServerCapabilities {
    /// Whether people's chats take voice messages: SendMessage takes `voiceMessage`.
    public var offersVoiceMessages: Bool { sendMessageArgumentNames.contains("voiceMessage") }

    /// Whether calls can be made: the server has the operations. Whether a media host is alive is a separate question, `isChatCallAvailable`.
    public var offersChatCalls: Bool {
        offersMutation("StartChatCall") && offersMutation("JoinChatCallMedia") && offersSubscription("OnChatCallEvent")
            && offersSubscription("OnChatCallSignal")
    }

    /// Whether the phone may choose which video it receives.
    public var offersVideoSelection: Bool { offersMutation("SetChatCallVideoSubscriptions") }

    /// Whether messages in a chat carry voice and call fields.
    public var offersChatMedia: Bool { offersVoiceMessages || offersChatCalls }
}

extension Connection {
    /// Whether a media host is alive. False hides the call buttons; voice messages still work.
    public func isChatCallAvailable() async -> Bool {
        struct Answer: Decodable, Sendable { let IsChatCallAvailable: Bool? }
        return (try? await execute(Documents.isChatCallAvailable, as: Answer.self).IsChatCallAvailable) ?? false
    }

    /// The most people a call holds, which the server decides. The app's own number stands in when it does not say.
    public func chatCallMaximumPersonCount() async -> Int {
        struct Answer: Decodable, Sendable { let GetChatCallMaximumPersonCount: Int? }
        let count = try? await execute(Documents.getChatCallMaximumPersonCount, as: Answer.self).GetChatCallMaximumPersonCount
        return (count ?? 0) > 0 ? count! : ChatCallRules.maximumParticipants
    }

    /// Tells the server how much of each person's video this phone wants. People not named keep their earlier choice. A long list goes in
    /// requests of at most 64.
    public func setChatCallVideoSubscriptions(id: String, subscriptions: [(userId: String, videoQuality: VideoQuality)]) async throws {
        var start = 0
        while start < subscriptions.count {
            let chunk = subscriptions[start..<min(start + CallSubscriptionPlan.maximumEntriesPerRequest, subscriptions.count)]
            let entries: [JSONValue] = chunk.map { .object(["userId": .string($0.userId), "videoQuality": .string($0.videoQuality.rawValue)]) }
            _ = try await execute(
                Documents.setChatCallVideoSubscriptions, variables: ["callId": .string(id), "subscriptions": .array(entries)], as: JSONValue.self)
            start += CallSubscriptionPlan.maximumEntriesPerRequest
        }
    }

    public func goingChatCalls() async throws -> [ChatCall] {
        struct Answer: Decodable, Sendable { let ListGoingChatCalls: [ChatCall]? }
        return try await execute(Documents.listGoingChatCalls, as: Answer.self).ListGoingChatCalls ?? []
    }

    public func chatCall(id: String) async throws -> ChatCall {
        struct Answer: Decodable, Sendable { let GetChatCall: ChatCall? }
        guard let call = try await execute(Documents.getChatCall, variables: ["callId": .string(id)], as: Answer.self).GetChatCall else {
            throw PortalError.refused("Call not found.")
        }
        return call
    }

    /// Starts a call, ringing `userIds`, or every member when nil. A chat that already has a going call returns that call, and
    /// `isExisting` is true: the person is not on it yet and must join it.
    public func startChatCall(chatId: String, userIds: [String]?, isVideoOn: Bool) async throws -> (call: ChatCall, isExisting: Bool) {
        struct Answer: Decodable, Sendable {
            struct Started: Decodable, Sendable {
                let call: ChatCall?
                let isExistingCall: Bool?
            }
            let StartChatCall: Started?
        }
        var variables: [String: JSONValue] = ["chatId": .string(chatId), "isVideoOn": .bool(isVideoOn)]
        if let userIds { variables["userIds"] = .array(userIds.map { .string($0) }) }
        let started = try await execute(Documents.startChatCall, variables: variables, as: Answer.self).StartChatCall
        guard let call = started?.call else { throw PortalError.unreadableAnswer }
        return (call, started?.isExistingCall == true)
    }

    public func joinChatCall(id: String) async throws -> ChatCall {
        struct Answer: Decodable, Sendable {
            struct Joined: Decodable, Sendable { let call: ChatCall? }
            let JoinChatCall: Joined?
        }
        var variables: [String: JSONValue] = ["callId": .string(id)]
        if let deviceId = PushDeviceIdentity.stored(accountKey: accountKey) { variables["pushDeviceId"] = .string(deviceId) }
        guard let call = try await execute(Documents.joinChatCall, variables: variables, as: Answer.self).JoinChatCall?.call else {
            throw PortalError.unreadableAnswer
        }
        return call
    }

    public func declineChatCall(id: String) async throws {
        var variables: [String: JSONValue] = ["callId": .string(id)]
        if let deviceId = PushDeviceIdentity.stored(accountKey: accountKey) { variables["pushDeviceId"] = .string(deviceId) }
        _ = try await execute(Documents.declineChatCall, variables: variables, as: JSONValue.self)
    }

    public func leaveChatCall(id: String) async throws {
        _ = try await execute(Documents.leaveChatCall, variables: ["callId": .string(id)], as: JSONValue.self)
    }

    public func ringChatCallMembers(id: String, userIds: [String]) async throws {
        _ = try await execute(
            Documents.ringChatCallMembers, variables: ["callId": .string(id), "userIds": .array(userIds.map { .string($0) })], as: JSONValue.self)
    }

    public func setChatCallMedia(id: String, isMuted: Bool, isVideoOn: Bool) async throws {
        _ = try await execute(
            Documents.setChatCallMedia, variables: ["callId": .string(id), "isMuted": .bool(isMuted), "isVideoOn": .bool(isVideoOn)], as: JSONValue.self)
    }

    public func setChatCallTranscription(id: String, isTranscriptionOn: Bool) async throws {
        _ = try await execute(
            Documents.setChatCallTranscription, variables: ["callId": .string(id), "isTranscriptionOn": .bool(isTranscriptionOn)], as: JSONValue.self)
    }

    /// Joins the media of a call with the phone's offer (made after its candidates were gathered) and returns the server's answer.
    public func joinChatCallMedia(id: String, offerSdp: String) async throws -> String {
        struct Answer: Decodable, Sendable {
            struct Joined: Decodable, Sendable { let answerSdp: String? }
            let JoinChatCallMedia: Joined?
        }
        let variables: [String: JSONValue] = ["callId": .string(id), "offerSdp": .string(offerSdp)]
        guard let sdp = try await execute(Documents.joinChatCallMedia, variables: variables, as: Answer.self).JoinChatCallMedia?.answerSdp, !sdp.isEmpty
        else { throw PortalError.unreadableAnswer }
        return sdp
    }

    /// Answers an offer the server made to renegotiate.
    public func answerChatCallMedia(id: String, answerSdp: String) async throws {
        _ = try await execute(Documents.answerChatCallMedia, variables: ["callId": .string(id), "answerSdp": .string(answerSdp)], as: JSONValue.self)
    }
}

/// ChatCallFeedUpdate is what a call feed tells its screen.
public enum ChatCallFeedUpdate: Equatable, Sendable {
    /// The socket is subscribed. Nothing said while it was down is replayed: read the going calls again.
    case connected
    case event(ChatCallEvent)
    case signal(ChatCallSignal)
    case reconnecting
    case signedOut
}

/// ChatCallFeed streams the account's call events (OnChatCallEvent) and the media offers of one call (OnChatCallSignal),
/// with the keep-alive, token renewal and reconnect of every other feed.
public enum ChatCallFeed {
    public static func events(
        connection: Connection, socketFactory: @escaping FeedSocketFactory, timing: FeedTiming = FeedTiming()
    ) -> AsyncStream<ChatCallFeedUpdate> {
        updates(
            request: SubscriptionRequest(query: Documents.onChatCallEvent, field: "OnChatCallEvent"), connection: connection,
            socketFactory: socketFactory, timing: timing
        ) { payload in
            (try? JSONDecoder().decode(ChatCallEvent.self, from: JSONEncoder().encode(payload))).map { .event($0) }
        }
    }

    public static func signals(
        connection: Connection, callId: String, socketFactory: @escaping FeedSocketFactory, timing: FeedTiming = FeedTiming()
    ) -> AsyncStream<ChatCallFeedUpdate> {
        updates(
            request: SubscriptionRequest(query: Documents.onChatCallSignal, variables: ["callId": .string(callId)], field: "OnChatCallSignal"),
            connection: connection, socketFactory: socketFactory, timing: timing
        ) { payload in
            (try? JSONDecoder().decode(ChatCallSignal.self, from: JSONEncoder().encode(payload))).map { .signal($0) }
        }
    }

    private static func updates(
        request: SubscriptionRequest, connection: Connection, socketFactory: @escaping FeedSocketFactory, timing: FeedTiming,
        read: @escaping @Sendable (JSONValue) -> ChatCallFeedUpdate?
    ) -> AsyncStream<ChatCallFeedUpdate> {
        let raw = SubscriptionFeed.updates(connection: connection, request: request, socketFactory: socketFactory, timing: timing)
        return AsyncStream { continuation in
            let task = Task {
                for await update in raw {
                    switch update {
                    case .connected: continuation.yield(.connected)
                    case .reconnecting: continuation.yield(.reconnecting)
                    case .signedOut: continuation.yield(.signedOut)
                    case .payload(let payload):
                        if let mapped = read(payload) { continuation.yield(mapped) }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
