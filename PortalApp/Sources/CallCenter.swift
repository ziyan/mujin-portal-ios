@preconcurrency import AVFoundation
@preconcurrency import CallKit
import Foundation
import Observation
import PortalKit
import UIKit

/// CallCenter is the one place that knows about the call this phone is in, or the call that is ringing on it: it answers the system's
/// call UI, the VoIP pushes, and the app's own buttons. Only one call is on at a time.
@MainActor
@Observable
final class CallCenter: CallKitHandling {
    /// A ring the system is showing and the person has not answered.
    private struct Ring {
        let payload: VoipPushPayload
    }

    private(set) var session: ChatCallSession?
    /// Whether the call screen covers the app. A call that is on but not shown is the minimized bar.
    var isScreenShown = false
    /// What the last attempt to start a call said, for the screen that asked.
    var startErrorText: String?

    @ObservationIgnored weak var appModel: AppModel?
    @ObservationIgnored private let callKit: CallKitController?
    @ObservationIgnored private let voip = VoipRegistry()
    @ObservationIgnored private var rings: [UUID: Ring] = [:]
    @ObservationIgnored private var pendingSessions: [UUID: ChatCallSession] = [:]
    let isDemo: Bool

    init(isDemo: Bool) {
        self.isDemo = isDemo
        callKit = isDemo ? nil : CallKitController()
        callKit?.handler = self
        voip.center = self
    }

    /// Asks PushKit for the call token. Called once at launch.
    func startPushKit() {
        guard !isDemo else { return }
        voip.start()
    }

    var isInCall: Bool { session != nil && session?.isEnded == false }

    // MARK: starting from the app

    /// Starts a call in a chat, or joins the one going there. False when this phone is already on a call.
    @discardableResult
    func begin(
        entry: ChatCallSession.Entry, chatId: String, chatTitle: String, isVideoOn: Bool, account: Account, connection: Connection
    ) -> Bool {
        guard !isInCall, let appModel else { return false }
        let created = ChatCallSession(
            uuid: UUID(), entry: entry, chatId: chatId, chatTitle: chatTitle, userId: account.userId, connection: connection,
            socketFactory: appModel.socketFactory, isVideoOn: isVideoOn)
        attach(created)
        isScreenShown = true
        guard let callKit else {
            Task { await created.begin() }
            return true
        }
        pendingSessions[created.uuid] = created
        Task {
            let accepted = await callKit.requestStart(uuid: created.uuid, name: chatTitle, hasVideo: isVideoOn)
            if !accepted {
                // The system refused (another call is on): the call does not go ahead.
                pendingSessions[created.uuid] = nil
                if session === created { session = nil }
                isScreenShown = false
                startErrorText = String(localized: "A call is already on this phone.")
            }
        }
        return true
    }

    private func attach(_ created: ChatCallSession) {
        session = created
        created.onEnded = { [weak self] ended in self?.sessionEnded(ended) }
        created.onConnected = { [weak self] connected in self?.callKit?.reportConnected(uuid: connected.uuid) }
    }

    func show() { isScreenShown = true }
    func minimize() { isScreenShown = false }

    /// The hang up button: ends the call through the system when it knows the call, else directly.
    func hangUp() {
        guard let session else { return }
        if let callKit {
            Task { await callKit.requestEnd(uuid: session.uuid) }
        } else {
            Task { await session.leave() }
        }
    }

    func setMuted(_ isMuted: Bool) {
        guard let session else { return }
        if let callKit {
            Task { await callKit.requestMute(uuid: session.uuid, isMuted: isMuted) }
        } else {
            session.applyMuted(isMuted)
        }
    }

    private func sessionEnded(_ ended: ChatCallSession) {
        callKit?.reportEnded(uuid: ended.uuid, reason: .remoteEnded)
        pendingSessions[ended.uuid] = nil
        Task {
            // The screen says the call is over for a moment before it goes.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if session === ended {
                session = nil
                isScreenShown = false
            }
        }
    }

    // MARK: a ring from the server

    func handleVoipPush(_ payload: VoipPushPayload?, completion: @escaping @Sendable () -> Void) {
        guard let callKit else {
            completion()
            return
        }
        guard let payload else {
            // Not about a call: PushKit still wants a call reported, so one is reported and ended at once.
            reportAndEnd(callKit: callKit, completion: completion)
            return
        }
        switch payload.kind {
        case .ringing:
            let uuid = UUID()
            rings[uuid] = Ring(payload: payload)
            callKit.reportIncoming(uuid: uuid, name: payload.shownName, hasVideo: payload.isVideoOn) { [weak self] error in
                Task { @MainActor in
                    if error != nil { self?.rings[uuid] = nil } else { self?.checkRing(uuid: uuid) }
                }
                completion()
            }
        case .stopped:
            if let uuid = rings.first(where: { $0.value.payload.callId == payload.callId })?.key {
                rings[uuid] = nil
                callKit.reportEnded(uuid: uuid, reason: .answeredElsewhere)
                completion()
            } else {
                reportAndEnd(callKit: callKit, completion: completion)
            }
        }
    }

    private func reportAndEnd(callKit: CallKitController, completion: @escaping @Sendable () -> Void) {
        let uuid = UUID()
        callKit.reportIncoming(uuid: uuid, name: "Portal", hasVideo: false) { _ in
            Task { @MainActor in callKit.reportEnded(uuid: uuid, reason: .remoteEnded) }
            completion()
        }
    }

    /// The server's word on a ring just shown: if the call is over or was answered elsewhere, the ring is taken down.
    private func checkRing(uuid: UUID) {
        guard let ring = rings[uuid], let appModel, let account = appModel.account(forUserId: ring.payload.userId) else {
            if rings[uuid] != nil { endRing(uuid, reason: .failed) }
            return
        }
        let connection = appModel.connection(for: account)
        Task {
            guard let call = try? await connection.chatCall(id: ring.payload.callId) else { return }
            guard rings[uuid] != nil else { return }
            if !call.isGoing || !call.isRinging(userId: account.userId) {
                endRing(uuid, reason: call.isGoing ? .answeredElsewhere : .remoteEnded)
            } else {
                callKit?.reportDetails(uuid: uuid, name: call.startedByUserName ?? ring.payload.shownName, hasVideo: ring.payload.isVideoOn)
            }
        }
    }

    private func endRing(_ uuid: UUID, reason: CXCallEndedReason) {
        rings[uuid] = nil
        callKit?.reportEnded(uuid: uuid, reason: reason)
    }

    /// The account's call feed says a ring stopped, such as answered on another device.
    func stopRinging(callId: String) {
        for (uuid, ring) in rings where ring.payload.callId == callId { endRing(uuid, reason: .answeredElsewhere) }
    }

    // MARK: CallKitHandling

    func callKitStart(uuid: UUID, hasVideo: Bool) -> Bool {
        guard let pending = pendingSessions.removeValue(forKey: uuid) else { return false }
        callKit?.reportConnecting(uuid: uuid)
        Task { await pending.begin() }
        return true
    }

    func callKitAnswer(uuid: UUID) -> Bool {
        guard let ring = rings[uuid], !isInCall, let appModel, let account = appModel.account(forUserId: ring.payload.userId) else { return false }
        rings[uuid] = nil
        let created = ChatCallSession(
            uuid: uuid, entry: .join(callId: ring.payload.callId), chatId: ring.payload.chatId ?? "", chatTitle: ring.payload.shownName, userId: account.userId,
            connection: appModel.connection(for: account), socketFactory: appModel.socketFactory, isVideoOn: ring.payload.isVideoOn)
        attach(created)
        isScreenShown = true
        Task { await created.begin() }
        return true
    }

    func callKitEnd(uuid: UUID) -> Bool {
        if let ring = rings.removeValue(forKey: uuid) {
            // Declined from the system's screen.
            if let appModel, let account = appModel.account(forUserId: ring.payload.userId) {
                let connection = appModel.connection(for: account)
                Task { try? await connection.declineChatCall(id: ring.payload.callId) }
            }
            return true
        }
        if pendingSessions.removeValue(forKey: uuid) != nil { return true }
        if let session, session.uuid == uuid { Task { await session.leave() } }
        return true
    }

    func callKitSetMuted(uuid: UUID, isMuted: Bool) {
        if let session, session.uuid == uuid { session.applyMuted(isMuted) }
    }

    func callKitAudioActivated(_ audioSession: AVAudioSession) {
        CallMedia.audioSessionDidActivate(audioSession)
        session?.audioDidActivate()
    }

    func callKitAudioDeactivated(_ audioSession: AVAudioSession) {
        CallMedia.audioSessionDidDeactivate(audioSession)
    }

    func callKitReset() {
        rings = [:]
        pendingSessions = [:]
        if let session { Task { await session.leave() } }
    }

    // MARK: demo

    func showDemo(_ demo: ChatCallSession, isScreenShown: Bool) {
        session = demo
        self.isScreenShown = isScreenShown
    }
}
