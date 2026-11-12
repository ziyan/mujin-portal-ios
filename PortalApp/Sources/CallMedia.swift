@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import SwiftUI
import UIKit
@preconcurrency import WebRTC

/// VideoTrackBox carries a video track to the screen that draws it.
final class VideoTrackBox: @unchecked Sendable, Identifiable {
    let id = UUID()
    fileprivate let track: RTCVideoTrack
    fileprivate init(_ track: RTCVideoTrack) { self.track = track }
}

enum CallMediaError: Error {
    case noPeerConnection
    case negotiationFailed
}

/// CallMedia is the phone's side of a call's media: one WebRTC connection to the server, the microphone, the camera, and the
/// streams of the other people. The server is ICE-lite with one address, so no ICE servers are given and the offer is sent once
/// the phone's own candidates are gathered. Everything the screen needs comes back through the callbacks.
final class CallMedia: NSObject, RTCPeerConnectionDelegate, @unchecked Sendable {
    /// A remote stream's id is the id of the person who sends it.
    /// What the call does anything about; the states in between are `other`.
    enum ConnectionState: Sendable {
        case connected
        case disconnected
        case failed
        case other
    }

    struct Callbacks: @unchecked Sendable {
        var onRemoteVideo: @Sendable (_ userId: String, _ box: VideoTrackBox?) -> Void = { _, _ in }
        var onConnectionChange: @Sendable (_ state: ConnectionState) -> Void = { _ in }
        var onSpeaking: @Sendable (_ userIds: Set<String>) -> Void = { _ in }
    }

    nonisolated(unsafe) private static let factory: RTCPeerConnectionFactory = {
        // WebRTC takes the audio session only when told: CallKit decides when the session is active.
        let audioSession = RTCAudioSession.sharedInstance()
        audioSession.useManualAudio = true
        audioSession.isAudioEnabled = false
        return RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory())
    }()

    private let callbacks: Callbacks
    private let localUserId: String
    private var peerConnection: RTCPeerConnection?
    private var audioTrack: RTCAudioTrack?
    private var videoSource: RTCVideoSource?
    private var videoTrack: RTCVideoTrack?
    private var videoSender: RTCRtpSender?
    private var capturer: RTCCameraVideoCapturer?
    private var cameraPosition = AVCaptureDevice.Position.front
    private let lock = NSLock()
    private var gatheringWaiters: [CheckedContinuation<Void, Never>] = []
    private var trackOwners: [String: String] = [:]
    private var statisticsTask: Task<Void, Never>?
    private(set) var localVideoBox: VideoTrackBox?

    init(localUserId: String, callbacks: Callbacks) {
        self.localUserId = localUserId
        self.callbacks = callbacks
        super.init()
    }

    // MARK: audio session

    /// CallKit made the audio session active: WebRTC may use it now.
    static func audioSessionDidActivate(_ session: AVAudioSession) {
        let audioSession = RTCAudioSession.sharedInstance()
        audioSession.audioSessionDidActivate(session)
        audioSession.isAudioEnabled = true
    }

    static func audioSessionDidDeactivate(_ session: AVAudioSession) {
        let audioSession = RTCAudioSession.sharedInstance()
        audioSession.audioSessionDidDeactivate(session)
        audioSession.isAudioEnabled = false
    }

    // MARK: setup

    /// Makes the connection with the microphone, and a video line the camera joins later by replacing its track.
    func prepare(isVideoOn: Bool) throws {
        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        configuration.iceServers = []
        configuration.continualGatheringPolicy = .gatherOnce
        configuration.bundlePolicy = .maxBundle
        configuration.rtcpMuxPolicy = .require
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let connection = Self.factory.peerConnection(with: configuration, constraints: constraints, delegate: self) else {
            throw CallMediaError.noPeerConnection
        }
        peerConnection = connection

        let audioSource = Self.factory.audioSource(with: constraints)
        let microphone = Self.factory.audioTrack(with: audioSource, trackId: "audio-\(localUserId)")
        audioTrack = microphone
        let audioInit = RTCRtpTransceiverInit()
        audioInit.direction = .sendRecv
        audioInit.streamIds = [localUserId]
        _ = connection.addTransceiver(with: microphone, init: audioInit)

        let source = Self.factory.videoSource()
        videoSource = source
        let camera = Self.factory.videoTrack(with: source, trackId: "video-\(localUserId)")
        videoTrack = camera
        localVideoBox = VideoTrackBox(camera)
        let videoInit = RTCRtpTransceiverInit()
        videoInit.direction = .sendRecv
        videoInit.streamIds = [localUserId]
        // One track, two encodings: the server forwards the layer each viewer asked for.
        videoInit.sendEncodings = Self.simulcastEncodings()
        // The video line is always in the offer, so turning the camera on later needs no new negotiation.
        let transceiver = connection.addTransceiver(of: .video, init: videoInit)
        videoSender = transceiver?.sender
        if let transceiver { Self.preferVideoCodecs(transceiver) }
        capturer = RTCCameraVideoCapturer(delegate: source)
        startStatistics()
    }

    /// The two layers: rid `small` at a quarter of the size (320 by 180 from 720p) up to 150 kbps and 15 frames a second, and rid `full` at the
    /// camera's size up to 1.5 Mbps and 30 frames a second.
    private static func simulcastEncodings() -> [RTCRtpEncodingParameters] {
        let small = RTCRtpEncodingParameters()
        small.rid = "small"
        small.isActive = true
        small.scaleResolutionDownBy = NSNumber(value: 4.0)
        small.maxBitrateBps = NSNumber(value: 150_000)
        small.maxFramerate = NSNumber(value: 15)
        let full = RTCRtpEncodingParameters()
        full.rid = "full"
        full.isActive = true
        full.scaleResolutionDownBy = NSNumber(value: 1.0)
        full.maxBitrateBps = NSNumber(value: 1_500_000)
        full.maxFramerate = NSNumber(value: 30)
        return [small, full]
    }

    /// The server takes VP8 and H.264 only, and software VP8 is the codec WebRTC simulcasts most dependably, so VP8 comes first.
    private static func preferVideoCodecs(_ transceiver: RTCRtpTransceiver) {
        let capabilities = factory.rtpReceiverCapabilities(forKind: kRTCMediaStreamTrackKindVideo)
        var ordered: [RTCRtpCodecCapability] = []
        for name in ["vp8", "h264"] { ordered += capabilities.codecs.filter { $0.name.lowercased() == name } }
        guard !ordered.isEmpty else { return }
        ordered += capabilities.codecs.filter { $0.name.lowercased() == "rtx" }
        try? transceiver.setCodecPreferences(ordered)
    }

    // MARK: negotiation

    /// The phone's offer, made once its candidates are gathered.
    func makeOffer() async throws -> String {
        guard let connection = peerConnection else { throw CallMediaError.noPeerConnection }
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.offer(for: constraints) { description, error in
                guard let description else {
                    continuation.resume(throwing: error ?? CallMediaError.negotiationFailed)
                    return
                }
                connection.setLocalDescription(description) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
        }
        await waitForGathering()
        guard let sdp = connection.localDescription?.sdp else { throw CallMediaError.negotiationFailed }
        return sdp
    }

    func acceptAnswer(_ sdp: String) async throws {
        guard let connection = peerConnection else { throw CallMediaError.noPeerConnection }
        let description = RTCSessionDescription(type: .answer, sdp: sdp)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.setRemoteDescription(description) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    /// Answers an offer the server made, and returns the answer to send back.
    func answer(toOffer sdp: String) async throws -> String {
        guard let connection = peerConnection else { throw CallMediaError.noPeerConnection }
        let offer = RTCSessionDescription(type: .offer, sdp: sdp)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.setRemoteDescription(offer) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.answer(for: constraints) { description, error in
                guard let description else {
                    continuation.resume(throwing: error ?? CallMediaError.negotiationFailed)
                    return
                }
                connection.setLocalDescription(description) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
        }
        guard let answer = connection.localDescription?.sdp else { throw CallMediaError.negotiationFailed }
        return answer
    }

    private func waitForGathering() async {
        guard let connection = peerConnection, connection.iceGatheringState != .complete else { return }
        let timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            self?.finishGathering()
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if connection.iceGatheringState == .complete {
                lock.unlock()
                continuation.resume()
            } else {
                gatheringWaiters.append(continuation)
                lock.unlock()
            }
        }
        timeout.cancel()
    }

    private func finishGathering() {
        lock.lock()
        let waiters = gatheringWaiters
        gatheringWaiters = []
        lock.unlock()
        for waiter in waiters { waiter.resume() }
    }

    // MARK: microphone and camera

    func setMuted(_ isMuted: Bool) { audioTrack?.isEnabled = !isMuted }

    /// Turns the camera on or off. Off replaces the sent track with nothing and stops the camera. False when the camera would not open.
    func setCameraOn(_ isOn: Bool) async -> Bool {
        guard let sender = videoSender, let videoTrack else { return false }
        if isOn {
            guard await startCapture(position: cameraPosition) else { return false }
            sender.track = videoTrack
            return true
        }
        sender.track = nil
        await stopCapture()
        return true
    }

    /// Turns to the other camera. If it will not open, the one before comes back. Returns whether the position changed.
    func switchCamera() async -> Bool {
        let previous = cameraPosition
        let next: AVCaptureDevice.Position = previous == .front ? .back : .front
        await stopCapture()
        if await startCapture(position: next) {
            cameraPosition = next
            return true
        }
        _ = await startCapture(position: previous)
        cameraPosition = previous
        return false
    }

    var isFrontCamera: Bool { cameraPosition == .front }

    private func startCapture(position: AVCaptureDevice.Position) async -> Bool {
        guard let capturer, let device = RTCCameraVideoCapturer.captureDevices().first(where: { $0.position == position }) else { return false }
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        // 720p, so the full layer is 1280 by 720 and the small one 320 by 180.
        let wanted = 1280
        guard let format = formats.min(by: {
            abs(Int(CMVideoFormatDescriptionGetDimensions($0.formatDescription).width) - wanted)
                < abs(Int(CMVideoFormatDescriptionGetDimensions($1.formatDescription).width) - wanted)
        }) else { return false }
        let frameRate = min(30, Int(format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 30))
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            capturer.startCapture(with: device, format: format, fps: frameRate) { error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    private func stopCapture() async {
        guard let capturer else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            capturer.stopCapture { continuation.resume() }
        }
    }

    // MARK: end

    func close() async {
        statisticsTask?.cancel()
        statisticsTask = nil
        await stopCapture()
        videoSender?.track = nil
        peerConnection?.close()
        peerConnection = nil
        audioTrack = nil
        videoTrack = nil
        localVideoBox = nil
        finishGathering()
    }

    // MARK: who is speaking

    private func startStatistics() {
        statisticsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard let self, let connection = self.peerConnection else { return }
                let speaking = await self.speakingUserIds(connection)
                self.callbacks.onSpeaking(speaking)
            }
        }
    }

    private func speakingUserIds(_ connection: RTCPeerConnection) async -> Set<String> {
        await withCheckedContinuation { (continuation: CheckedContinuation<Set<String>, Never>) in
            connection.statistics { report in
                var speaking: Set<String> = []
                for (_, statistics) in report.statistics {
                    guard let level = (statistics.values["audioLevel"] as? NSNumber)?.doubleValue, level > 0.02 else { continue }
                    if statistics.type == "media-source", (statistics.values["kind"] as? String) == "audio" {
                        speaking.insert(self.localUserId)
                    } else if statistics.type == "inbound-rtp", (statistics.values["kind"] as? String) == "audio",
                        let trackId = statistics.values["trackIdentifier"] as? String
                    {
                        self.lock.lock()
                        let owner = self.trackOwners[trackId]
                        self.lock.unlock()
                        if let owner { speaking.insert(owner) }
                    }
                }
                continuation.resume(returning: speaking)
            }
        }
    }

    // MARK: RTCPeerConnectionDelegate

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        if newState == .complete { finishGathering() }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        switch newState {
        case .connected: callbacks.onConnectionChange(.connected)
        case .disconnected: callbacks.onConnectionChange(.disconnected)
        case .failed: callbacks.onConnectionChange(.failed)
        default: callbacks.onConnectionChange(.other)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        guard let owner = mediaStreams.first?.streamId, owner != localUserId, let track = rtpReceiver.track else { return }
        lock.lock()
        trackOwners[track.trackId] = owner
        lock.unlock()
        if let video = track as? RTCVideoTrack { callbacks.onRemoteVideo(owner, VideoTrackBox(video)) }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove rtpReceiver: RTCRtpReceiver) {
        guard let track = rtpReceiver.track else { return }
        lock.lock()
        let owner = trackOwners.removeValue(forKey: track.trackId)
        lock.unlock()
        if track is RTCVideoTrack, let owner { callbacks.onRemoteVideo(owner, nil) }
    }
}

/// CallVideoView draws a video track, filling its frame. Without a track it draws nothing.
struct CallVideoView: UIViewRepresentable {
    let box: VideoTrackBox?
    var isMirrored = false

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView()
        view.videoContentMode = .scaleAspectFill
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: RTCMTLVideoView, context: Context) {
        view.transform = isMirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
        if context.coordinator.box?.id == box?.id { return }
        context.coordinator.box?.track.remove(view)
        context.coordinator.box = box
        box?.track.add(view)
    }

    static func dismantleUIView(_ view: RTCMTLVideoView, coordinator: Coordinator) {
        coordinator.box?.track.remove(view)
        coordinator.box = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var box: VideoTrackBox?
    }
}
