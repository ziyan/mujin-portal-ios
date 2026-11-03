@preconcurrency import AVFoundation
@preconcurrency import CallKit
import Foundation
@preconcurrency import PushKit
import PortalKit

/// CallKitHandling is what the app does when the system, or the person on the system's call screen, acts on a call.
@MainActor
protocol CallKitHandling: AnyObject {
    /// The person started a call from the app. True lets the system go on.
    func callKitStart(uuid: UUID, hasVideo: Bool) -> Bool
    /// The person answered a ringing call.
    func callKitAnswer(uuid: UUID) -> Bool
    /// The person ended or declined the call from the system's screen, or the app asked it to end.
    func callKitEnd(uuid: UUID) -> Bool
    func callKitSetMuted(uuid: UUID, isMuted: Bool)
    func callKitAudioActivated(_ session: AVAudioSession)
    func callKitAudioDeactivated(_ session: AVAudioSession)
    func callKitReset()
}

/// CallKitController is the app's line to the system's call UI: video is supported, calls stay out of Recents, and there is no hold.
@MainActor
final class CallKitController: NSObject, CXProviderDelegate {
    private let provider: CXProvider
    private let callController = CXCallController()
    weak var handler: CallKitHandling?

    override init() {
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = true
        configuration.includesCallsInRecents = false
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: .main)
    }

    private func update(name: String, hasVideo: Bool) -> CXCallUpdate {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: name)
        update.localizedCallerName = name
        update.hasVideo = hasVideo
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false
        return update
    }

    // MARK: reports to the system

    func reportIncoming(uuid: UUID, name: String, hasVideo: Bool, completion: @escaping (Error?) -> Void) {
        provider.reportNewIncomingCall(with: uuid, update: update(name: name, hasVideo: hasVideo)) { error in completion(error) }
    }

    func reportDetails(uuid: UUID, name: String, hasVideo: Bool) {
        provider.reportCall(with: uuid, updated: update(name: name, hasVideo: hasVideo))
    }

    func reportEnded(uuid: UUID, reason: CXCallEndedReason) {
        provider.reportCall(with: uuid, endedAt: Date(), reason: reason)
    }

    func reportConnecting(uuid: UUID) { provider.reportOutgoingCall(with: uuid, startedConnectingAt: Date()) }
    func reportConnected(uuid: UUID) { provider.reportOutgoingCall(with: uuid, connectedAt: Date()) }

    // MARK: requests from the app

    func requestStart(uuid: UUID, name: String, hasVideo: Bool) async -> Bool {
        let action = CXStartCallAction(call: uuid, handle: CXHandle(type: .generic, value: name))
        action.isVideo = hasVideo
        action.contactIdentifier = name
        return await request(action)
    }

    func requestEnd(uuid: UUID) async { _ = await request(CXEndCallAction(call: uuid)) }

    func requestMute(uuid: UUID, isMuted: Bool) async { _ = await request(CXSetMutedCallAction(call: uuid, muted: isMuted)) }

    private func request(_ action: CXAction) async -> Bool {
        do {
            try await callController.request(CXTransaction(action: action))
            return true
        } catch {
            return false
        }
    }

    // MARK: CXProviderDelegate

    nonisolated func providerDidReset(_ provider: CXProvider) {
        MainActor.assumeIsolated { handler?.callKitReset() }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        MainActor.assumeIsolated {
            if handler?.callKitStart(uuid: action.callUUID, hasVideo: action.isVideo) == true { action.fulfill() } else { action.fail() }
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        MainActor.assumeIsolated {
            if handler?.callKitAnswer(uuid: action.callUUID) == true { action.fulfill() } else { action.fail() }
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        MainActor.assumeIsolated {
            _ = handler?.callKitEnd(uuid: action.callUUID)
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        MainActor.assumeIsolated {
            handler?.callKitSetMuted(uuid: action.callUUID, isMuted: action.isMuted)
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        MainActor.assumeIsolated { handler?.callKitAudioActivated(audioSession) }
    }

    nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        MainActor.assumeIsolated { handler?.callKitAudioDeactivated(audioSession) }
    }
}

/// VoipRegistry asks PushKit for the phone's call token and hands each VoIP push to the call center. A VoIP push must be
/// reported to CallKit before it is finished, or the system ends the app, so a push that is not about a call is still reported, then ended.
@MainActor
final class VoipRegistry: NSObject, PKPushRegistryDelegate {
    private var registry: PKPushRegistry?
    weak var center: CallCenter?

    func start() {
        guard registry == nil else { return }
        let created = PKPushRegistry(queue: .main)
        created.delegate = self
        created.desiredPushTypes = [.voIP]
        registry = created
    }

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        let token = pushCredentials.token
        MainActor.assumeIsolated {
            VoipDeviceToken.store(token)
            Task { await AppModel.shared.registerPushDevices() }
        }
    }

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {}

    nonisolated func pushRegistry(
        _ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void
    ) {
        let parsed = VoipPushPayload(userInfo: payload.dictionaryPayload)
        MainActor.assumeIsolated {
            guard let center else {
                completion()
                return
            }
            center.handleVoipPush(parsed, completion: completion)
        }
    }
}
