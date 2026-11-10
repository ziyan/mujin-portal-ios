@preconcurrency import AVFoundation
import Foundation
import Network
import Observation
import PortalKit
import SwiftUI

/// CallParticipant is one tile of the call screen.
struct CallParticipant: Identifiable, Equatable {
    let userId: String
    let name: String
    let isSelf: Bool
    let isMuted: Bool
    let isVideoOn: Bool
    let isSpeaking: Bool
    let isRinging: Bool
    let videoId: UUID?
    var id: String { userId }
}

/// ChatCallSession is the phone's part in one call: it starts or joins the call on the server, negotiates the media, follows the
/// call's events, and holds what the call screen and the minimized bar show. There is at most one at a time.
@MainActor
@Observable
final class ChatCallSession: Identifiable {
    enum Phase: Equatable {
        case starting
        case connecting
        case connected
        /// The media dropped and is being replaced; the person is still on the call.
        case reconnecting
        case ended
    }

    enum Entry: Equatable {
        /// Starts a call, ringing `userIds` or everyone when nil.
        case start(userIds: [String]?)
        /// Joins a call that is going, from a ring or from the banner.
        case join(callId: String)
    }

    let uuid: UUID
    let entry: Entry
    let chatId: String
    let chatTitle: String
    let userId: String
    let connection: Connection?
    let isDemo: Bool

    private(set) var callId: String?
    private(set) var call: ChatCall?
    private(set) var phase = Phase.starting
    private(set) var isMuted = false
    private(set) var isCameraOn: Bool
    private(set) var isFrontCamera = true
    private(set) var remoteVideo: [String: VideoTrackBox] = [:]
    private(set) var localVideo: VideoTrackBox?
    private(set) var speakingUserIds: Set<String> = []
    /// Who is on the main stage of the speaker view while the phone follows the speaker.
    private(set) var activeSpeakerId: String?
    /// The person the viewer tapped to keep on the main stage, or nil to follow the speaker.
    private(set) var pinnedUserId: String?
    /// How much of each person's video the screen wants now: full for the main stage, small for the strip tiles in view, off for the rest.
    private(set) var subscriptionPlan: [String: VideoQuality] = [:]
    private(set) var now = Date()
    private(set) var routeSymbol = "iphone"
    private(set) var errorText: String?
    private(set) var connectedAt: Date?

    /// Told when the call is over, whoever ended it.
    var onEnded: ((ChatCallSession) -> Void)?
    var onConnected: ((ChatCallSession) -> Void)?

    private var media: CallMedia?
    private var queue: CallSignalQueue?
    private var eventTask: Task<Void, Never>?
    private var signalTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var routeObserver: NSObjectProtocol?
    private var hasLeft = false
    private var lastAnsweredSequence: Int?
    /// The session the server gave this phone, named when it reconnects.
    @ObservationIgnored private var mediaSessionId: String?
    /// Counts the connections made, so a late report from a closed one is ignored.
    @ObservationIgnored private var mediaGeneration = 0
    @ObservationIgnored private var firstConnectTask: Task<Void, Never>?
    @ObservationIgnored private var disconnectTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    /// The wait between attempts, which a change of network ends early.
    @ObservationIgnored private var reconnectWait: Task<Void, Never>?
    @ObservationIgnored private var networkMonitor: NWPathMonitor?
    @ObservationIgnored private var speaker = ActiveSpeaker()
    @ObservationIgnored private var lastSentPlan: [String: VideoQuality] = [:]
    @ObservationIgnored private var subscriptionFailureCount = 0
    @ObservationIgnored private var subscriptionTask: Task<Void, Never>?
    @ObservationIgnored private var isVideoSelectionUnsupported = false
    /// Whether the call screen is in front. A minimized call asks for no video.
    private(set) var isScreenShown = true
    private let socketFactory: FeedSocketFactory?

    init(
        uuid: UUID, entry: Entry, chatId: String, chatTitle: String, userId: String, connection: Connection?, socketFactory: FeedSocketFactory?,
        isVideoOn: Bool, isDemo: Bool = false
    ) {
        self.uuid = uuid
        self.entry = entry
        self.chatId = chatId
        self.chatTitle = chatTitle
        self.userId = userId
        self.connection = connection
        self.socketFactory = socketFactory
        self.isCameraOn = isVideoOn
        self.isDemo = isDemo
        if case .join(let callId) = entry { self.callId = callId }
    }

    // MARK: what the screens read

    var participants: [CallParticipant] {
        var tiles: [CallParticipant] = []
        let members = call?.allMembers ?? []
        let selfTile = CallParticipant(
            userId: userId, name: String(localized: "You"), isSelf: true, isMuted: isMuted, isVideoOn: isCameraOn, isSpeaking: speakingUserIds.contains(userId) && !isMuted,
            isRinging: false, videoId: localVideo?.id)
        tiles.append(selfTile)
        for member in members where member.userId != userId && (member.isOnCall || member.isRinging) {
            tiles.append(
                CallParticipant(
                    userId: member.userId, name: member.shownName, isSelf: false, isMuted: member.isMuted == true, isVideoOn: member.isVideoOn == true,
                    isSpeaking: speakingUserIds.contains(member.userId), isRinging: member.isRinging, videoId: remoteVideo[member.userId]?.id))
        }
        return tiles
    }

    func videoBox(for participant: CallParticipant) -> VideoTrackBox? {
        participant.isSelf ? localVideo : remoteVideo[participant.userId]
    }

    /// The people on the call now (not those being rung), the viewer first.
    var presentUserIds: [String] { participants.filter { !$0.isRinging }.map(\.userId) }

    /// Who is on the main stage of the speaker view: the pinned person, else the speaker.
    var mainUserId: String? {
        if let pinnedUserId, presentUserIds.contains(pinnedUserId) { return pinnedUserId }
        return activeSpeakerId
    }

    func pin(_ userId: String) { pinnedUserId = userId }
    func followSpeaker() { pinnedUserId = nil }

    func updateSpeaking(_ ids: Set<String>) {
        if speakingUserIds != ids { speakingUserIds = ids }
        refreshSpeaker()
    }

    func refreshSpeaker() {
        let chosen = speaker.update(speaking: speakingUserIds, candidates: presentUserIds, selfUserId: userId)
        if chosen != activeSpeakerId { activeSpeakerId = chosen }
    }

    /// What the screen shows: the speaker view with its strip tiles in view, or the stage and grid with their sizes. The server is told what
    /// changed after a short pause, once the media is up.
    func reportLayout(isSpeakerView: Bool, visibleStripUserIds: Set<String>, tileSizes: [String: CallSubscriptionPlan.TileSize]) {
        let plan = CallSubscriptionPlan.plan(
            remoteUserIds: presentUserIds.filter { $0 != userId }, mainUserId: mainUserId, visibleStripUserIds: visibleStripUserIds, isSpeakerView: isSpeakerView,
            tileSizes: tileSizes)
        if plan != subscriptionPlan {
            subscriptionPlan = plan
            scheduleSubscriptions()
        }
    }

    func setScreenShown(_ isShown: Bool) {
        guard isScreenShown != isShown else { return }
        isScreenShown = isShown
        scheduleSubscriptions()
    }

    /// The plan as the server should have it now: everyone off while minimized.
    private var effectivePlan: [String: VideoQuality] {
        isScreenShown ? subscriptionPlan : subscriptionPlan.mapValues { _ in VideoQuality.off }
    }

    private func scheduleSubscriptions(resendAll: Bool = false, delayNanoseconds: UInt64 = 300_000_000) {
        guard !isDemo, !isVideoSelectionUnsupported else { return }
        subscriptionTask?.cancel()
        subscriptionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.sendSubscriptions(resendAll: resendAll)
        }
    }

    private func sendSubscriptions(resendAll: Bool) async {
        guard phase == .connected, let connection, let callId else { return }
        let plan = effectivePlan
        let changes = CallSubscriptionPlan.changes(from: lastSentPlan, to: plan, resendAll: resendAll)
        guard !changes.isEmpty else { return }
        do {
            try await connection.setChatCallVideoSubscriptions(id: callId, subscriptions: changes)
            lastSentPlan = plan
            subscriptionFailureCount = 0
        } catch {
            guard (error as? PortalError) != .signedOut, !Task.isCancelled else { return }
            // A server without the mutation refuses it once and is not asked again; any other failure is tried again.
            if CallSubscriptionPlan.isSelectionUnsupported(by: error) {
                isVideoSelectionUnsupported = true
            } else {
                subscriptionFailureCount += 1
                if let delay = CallSubscriptionPlan.retryDelayNanoseconds(afterFailureCount: subscriptionFailureCount, error: error) {
                    scheduleSubscriptions(resendAll: resendAll, delayNanoseconds: delay)
                }
            }
        }
    }

    var hasVideoTiles: Bool { participants.contains { $0.isVideoOn } }
    var isEnded: Bool { phase == .ended }
    var startDate: Date? { connectedAt ?? call?.startDate }
    var elapsedText: String { ChatCallRules.elapsedText(since: startDate, now: now) }

    var statusText: String {
        switch phase {
        case .starting, .connecting: return String(localized: "Connecting\u{2026}")
        case .connected: return elapsedText
        case .reconnecting: return String(localized: "Reconnecting\u{2026}")
        case .ended: return String(localized: "Call ended")
        }
    }

    /// Said for as long as the call is recorded and transcribed, which calls are unless someone stops it. It cannot be dismissed.
    var recordingNotice: String? {
        isTranscriptionOn ? String(localized: "This call is being recorded and transcribed.") : nil
    }

    var isTranscriptionOn: Bool { call?.isTranscriptionOn == true }

    /// The members of the chat who could be rung.
    func peopleToRing(among chatMembers: [ChatMember]) -> [ChatMember] {
        guard let call else { return chatMembers.filter { $0.isPresent && $0.userId != userId } }
        return call.membersToRing(among: chatMembers, excluding: userId)
    }

    // MARK: beginning

    func begin() async {
        guard !isDemo, let connection, let socketFactory else { return }
        startClock()
        observeRoute()
        guard await askForMicrophone() else {
            fail(String(localized: "Allow the microphone in Settings to be on a call."))
            return
        }
        if isCameraOn, !(await askForCamera()) { isCameraOn = false }
        do {
            let joined: ChatCall
            switch entry {
            case .start(let userIds):
                let started = try await connection.startChatCall(chatId: chatId, userIds: userIds, isVideoOn: isCameraOn)
                // A chat that already had a call returns it: the person joins it before the media.
                joined = started.isExisting ? try await connection.joinChatCall(id: started.call.id) : started.call
            case .join(let callId):
                joined = try await connection.joinChatCall(id: callId)
            }
            callId = joined.id
            call = joined
            let activeCallId = joined.id
            let signalQueue = CallSignalQueue { [weak self] signal in await self?.handle(signal) }
            queue = signalQueue
            startFeeds(callId: activeCallId, connection: connection, socketFactory: socketFactory, queue: signalQueue)
            watchFirstConnect()
            observeNetwork()
            try await connectMedia(callId: activeCallId, connection: connection)
            await signalQueue.joinCompleted()
        } catch {
            fail(error.userMessage)
        }
    }

    private func connectMedia(callId: String, connection: Connection) async throws {
        phase = .connecting
        let created = try await makeMedia()
        let offer = try await created.makeOffer()
        let joined = try await connection.joinChatCallMedia(id: callId, offerSdp: offer)
        mediaSessionId = joined.mediaSessionId
        try await created.acceptAnswer(joined.answerSdp)
        // The others are told the camera is on (or off) once the media is joined: the server does not know it from the media
        try? await connection.setChatCallMedia(id: callId, isMuted: isMuted, isVideoOn: isCameraOn)
    }

    /// A new connection with the microphone and, when it is on, the camera. It replaces the one before, whose reports are ignored from now on.
    private func makeMedia() async throws -> CallMedia {
        mediaGeneration += 1
        let generation = mediaGeneration
        let callbacks = CallMedia.Callbacks(
            onRemoteVideo: { [weak self] userId, box in
                Task { @MainActor in
                    guard self?.mediaGeneration == generation else { return }
                    self?.setRemoteVideo(userId: userId, box: box)
                }
            },
            onConnectionChange: { [weak self] state in
                Task { @MainActor in
                    guard self?.mediaGeneration == generation else { return }
                    self?.mediaChanged(state)
                }
            },
            onSpeaking: { [weak self] ids in
                Task { @MainActor in self?.updateSpeaking(ids) }
            })
        let created = CallMedia(localUserId: userId, callbacks: callbacks)
        try created.prepare(isVideoOn: isCameraOn)
        media = created
        created.setMuted(isMuted)
        if isCameraOn {
            if await created.setCameraOn(true) { localVideo = created.localVideoBox } else { isCameraOn = false }
        }
        return created
    }

    // MARK: losing the media

    /// A first connection that never comes up has failed, rather than saying "Connecting" for ever.
    private func watchFirstConnect() {
        firstConnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(CallReconnectPlan.firstConnectTimeout * 1_000_000_000))
            guard !Task.isCancelled, let self, self.connectedAt == nil, self.phase != .ended else { return }
            self.fail(String(localized: "Could not connect to the call."))
        }
    }

    /// A change of network ends a wait: the old connection cannot recover on a network it did not gather for.
    private func observeNetwork() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in self?.networkChanged() }
        }
        monitor.start(queue: DispatchQueue(label: "call.network"))
        networkMonitor = monitor
    }

    private func networkChanged() {
        if disconnectTask != nil {
            disconnectTask?.cancel()
            disconnectTask = nil
            startReconnecting()
        }
        reconnectWait?.cancel()
    }

    private func startReconnecting() {
        guard phase == .connected, reconnectTask == nil, let connection, let callId, mediaSessionId != nil else {
            // A server that gave no session cannot reconnect the phone.
            if phase == .connected, mediaSessionId == nil { fail(String(localized: "The connection to the call was lost.")) }
            return
        }
        phase = .reconnecting
        let startedAt = Date()
        reconnectTask = Task { [weak self] in
            await self?.keepReconnecting(callId: callId, connection: connection, startedAt: startedAt)
        }
    }

    private func keepReconnecting(callId: String, connection: Connection, startedAt: Date) async {
        var failedAttempts = 0
        while !Task.isCancelled, phase == .reconnecting {
            if CallReconnectPlan.shouldGiveUp(elapsed: Date().timeIntervalSince(startedAt)) {
                reconnectTask = nil
                fail(String(localized: "The connection to the call was lost."))
                return
            }
            do {
                if try await attemptReconnect(callId: callId, connection: connection) { return }
            } catch let error as PortalError where error == .signedOut {
                reconnectTask = nil
                fail(error.userMessage)
                return
            } catch {
                // Nothing reached the server, or it could not take the call just now: try again.
            }
            failedAttempts += 1
            let delay = CallReconnectPlan.delay(afterFailedAttempts: failedAttempts)
            let wait = Task<Void, Never> { _ = try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            reconnectWait = wait
            await wait.value
            reconnectWait = nil
        }
    }

    /// One attempt, on a new connection. True when there is nothing more to try.
    private func attemptReconnect(callId: String, connection: Connection) async throws -> Bool {
        guard let session = mediaSessionId, let socketFactory else { return true }
        let closing = media
        media = nil
        remoteVideo = [:]
        await closing?.close()
        let created = try await makeMedia()
        let offer = try await created.makeOffer()
        // The offers of the new session wait for its answer, as on a first join. The old subscription may have ended with the session.
        let signalQueue = CallSignalQueue { [weak self] signal in await self?.handle(signal) }
        queue = signalQueue
        startSignals(callId: callId, connection: connection, socketFactory: socketFactory, queue: signalQueue)
        switch try await connection.reconnectChatCallMedia(id: callId, offerSdp: offer, mediaSessionId: session) {
        case .ended:
            stopReconnecting(message: nil)
            return true
        case .moved:
            stopReconnecting(message: String(localized: "The call moved to another device."))
            return true
        case .full:
            stopReconnecting(message: String(localized: "The call is full."))
            return true
        case .reconnected(let answerSdp, let newSession):
            mediaSessionId = newSession
            try await created.acceptAnswer(answerSdp)
            await signalQueue.joinCompleted()
            try? await connection.setChatCallMedia(id: callId, isMuted: isMuted, isVideoOn: isCameraOn)
            return await waitForConnection()
        }
    }

    /// True once the new connection is up. A connection that does not come up is replaced by the next attempt.
    private func waitForConnection() async -> Bool {
        let deadline = Date().addingTimeInterval(CallReconnectPlan.attemptTimeout)
        while Date() < deadline, !Task.isCancelled {
            if phase != .reconnecting { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return phase != .reconnecting
    }

    /// The server says this phone has no call to come back to, so there is nothing to leave.
    private func stopReconnecting(message: String?) {
        reconnectTask = nil
        hasLeft = true
        errorText = message
        finish()
    }

    private func askForMicrophone() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .undetermined: return await AVAudioApplication.requestRecordPermission()
        default: return false
        }
    }

    private func askForCamera() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    // MARK: following the call

    private func startFeeds(callId: String, connection: Connection, socketFactory: @escaping FeedSocketFactory, queue: CallSignalQueue) {
        eventTask = Task { [weak self] in
            for await update in ChatCallFeed.events(connection: connection, socketFactory: socketFactory) {
                guard let self else { return }
                switch update {
                case .event(let event) where event.resolvedCallId == callId:
                    if let changed = event.call { self.apply(changed) } else { await self.refresh() }
                case .connected:
                    await self.refresh()
                    self.scheduleSubscriptions(resendAll: true)
                default:
                    break
                }
            }
        }
        startSignals(callId: callId, connection: connection, socketFactory: socketFactory, queue: queue)
    }

    private func startSignals(callId: String, connection: Connection, socketFactory: @escaping FeedSocketFactory, queue: CallSignalQueue) {
        signalTask?.cancel()
        signalTask = Task {
            for await update in ChatCallFeed.signals(connection: connection, callId: callId, socketFactory: socketFactory) {
                if case .signal(let signal) = update { await queue.receive(signal) }
            }
        }
    }

    private func refresh() async {
        guard let connection, let callId, let fresh = try? await connection.chatCall(id: callId) else { return }
        apply(fresh)
    }

    func apply(_ fresh: ChatCall) {
        call = fresh
        refreshSpeaker()
        if !fresh.isGoing { finish() }
    }

    /// An offer from the server, which changes who is sent to the phone. Handled one at a time, in order.
    private func handle(_ signal: ChatCallSignal) async {
        // Sent when the person left or the call ended, never for a lost connection: there is nothing to come back to.
        if signal.signalKind == "closed" {
            hasLeft = true
            finish()
            return
        }
        // The server sends the latest unanswered offer again after a resubscribe: one already answered is ignored.
        if let sequence = signal.sequenceNumber {
            if let answered = lastAnsweredSequence, sequence <= answered { return }
            lastAnsweredSequence = sequence
        }
        guard let offer = signal.offerSdp, let media, let connection, let callId else { return }
        do {
            let answer = try await media.answer(toOffer: offer)
            try await connection.answerChatCallMedia(id: callId, answerSdp: answer)
        } catch {
            errorText = error.userMessage
        }
    }

    private func setRemoteVideo(userId: String, box: VideoTrackBox?) {
        if let box { remoteVideo[userId] = box } else { remoteVideo[userId] = nil }
    }

    private func mediaChanged(_ state: CallMedia.ConnectionState) {
        switch state {
        case .connected:
            disconnectTask?.cancel()
            disconnectTask = nil
            guard phase != .ended else { return }
            if phase != .connected {
                let isFirstConnection = connectedAt == nil
                phase = .connected
                reconnectTask = nil
                reconnectWait?.cancel()
                connectedAt = connectedAt ?? Date()
                firstConnectTask?.cancel()
                if isFirstConnection { onConnected?(self) }
            }
            // Each time the media comes up, first or after a reconnect, the server hears the whole plan again.
            scheduleSubscriptions(resendAll: true)
        case .disconnected:
            guard phase == .connected, disconnectTask == nil else { return }
            disconnectTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(CallReconnectPlan.disconnectedGrace * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                self.disconnectTask = nil
                self.startReconnecting()
            }
        case .failed:
            disconnectTask?.cancel()
            disconnectTask = nil
            // While reconnecting, the next attempt replaces a connection that failed.
            if phase == .connected {
                startReconnecting()
            } else if phase == .connecting || phase == .starting {
                fail(String(localized: "The connection to the call was lost."))
            }
        case .other:
            break
        }
    }

    // MARK: controls

    /// What CallKit asked: mute or unmute the microphone and tell the others.
    func applyMuted(_ value: Bool) {
        isMuted = value
        media?.setMuted(value)
        tellOthers()
    }

    func toggleCamera() {
        let wanted = !isCameraOn
        guard let media else {
            if isDemo { isCameraOn = wanted }
            return
        }
        Task {
            if await media.setCameraOn(wanted) {
                isCameraOn = wanted
                localVideo = wanted ? media.localVideoBox : nil
                tellOthers()
            } else {
                errorText = String(localized: "The camera could not be opened.")
            }
        }
    }

    func switchCamera() {
        if isDemo {
            isFrontCamera.toggle()
            return
        }
        guard let media, isCameraOn else { return }
        Task {
            let changed = await media.switchCamera()
            isFrontCamera = media.isFrontCamera
            if !changed { errorText = String(localized: "The other camera could not be opened.") }
        }
    }

    func setTranscription(_ isOn: Bool) {
        guard let connection, let callId else { return }
        Task {
            do {
                try await connection.setChatCallTranscription(id: callId, isTranscriptionOn: isOn)
                await refresh()
            } catch {
                errorText = error.userMessage
            }
        }
    }

    func ring(_ userIds: [String]) async -> String? {
        guard let connection, let callId, !userIds.isEmpty else { return nil }
        do {
            try await connection.ringChatCallMembers(id: callId, userIds: userIds)
            await refresh()
            return nil
        } catch {
            return error.userMessage
        }
    }

    func dismissError() { errorText = nil }

    private func tellOthers() {
        guard let connection, let callId else { return }
        let muted = isMuted
        let video = isCameraOn
        Task { try? await connection.setChatCallMedia(id: callId, isMuted: muted, isVideoOn: video) }
    }

    // MARK: ending

    /// Leaves the call on the server and lets go of the media.
    func leave() async {
        guard !hasLeft else { return }
        hasLeft = true
        if let connection, let callId { try? await connection.leaveChatCall(id: callId) }
        finish()
    }

    private func fail(_ message: String) {
        errorText = message
        finish()
    }

    private func finish() {
        guard phase != .ended else { return }
        phase = .ended
        firstConnectTask?.cancel()
        disconnectTask?.cancel()
        reconnectTask?.cancel()
        reconnectWait?.cancel()
        networkMonitor?.cancel()
        networkMonitor = nil
        subscriptionTask?.cancel()
        eventTask?.cancel()
        signalTask?.cancel()
        clockTask?.cancel()
        eventTask = nil
        signalTask = nil
        clockTask = nil
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
        routeObserver = nil
        let closing = media
        media = nil
        localVideo = nil
        remoteVideo = [:]
        Task { await closing?.close() }
        if !hasLeft, let connection, let callId {
            hasLeft = true
            Task { try? await connection.leaveChatCall(id: callId) }
        }
        onEnded?(self)
    }

    // MARK: clock and audio route

    private func startClock() {
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                self?.now = Date()
            }
        }
    }

    private func observeRoute() {
        refreshRoute()
        routeObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshRoute() }
        }
    }

    func refreshRoute() {
        routeSymbol = Self.symbol(for: AVAudioSession.sharedInstance().currentRoute.outputs.first?.portType)
    }

    /// The symbol that stands for where the sound goes now.
    static func symbol(for port: AVAudioSession.Port?) -> String {
        switch port {
        case .builtInSpeaker: return "speaker.wave.3.fill"
        case .headphones, .usbAudio, .headsetMic: return "headphones"
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE: return "airpods.gen3"
        case .airPlay: return "airplayaudio"
        case .carAudio: return "car.fill"
        default: return "iphone"
        }
    }

    /// CallKit made the audio session active. A video call starts on the speaker.
    func audioDidActivate() {
        if isCameraOn { try? AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker) }
        refreshRoute()
    }

    // MARK: demo

    /// A session the demo shows without a network: a call in progress with fixed people.
    static func demo(call: ChatCall, chatTitle: String, isCameraOn: Bool, elapsed: TimeInterval, speaking: Set<String>, isReconnecting: Bool = false) -> ChatCallSession {
        let session = ChatCallSession(
            uuid: UUID(), entry: .join(callId: call.id), chatId: call.chatId ?? "chat", chatTitle: chatTitle, userId: "user01", connection: nil, socketFactory: nil,
            isVideoOn: isCameraOn, isDemo: true)
        session.call = call
        session.callId = call.id
        session.phase = isReconnecting ? .reconnecting : .connected
        session.connectedAt = Date().addingTimeInterval(-elapsed)
        session.speakingUserIds = speaking
        session.refreshSpeaker()
        session.routeSymbol = "speaker.wave.3.fill"
        session.startClock()
        return session
    }
}
