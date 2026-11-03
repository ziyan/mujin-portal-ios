@preconcurrency import AVFoundation
import Foundation
import Observation
import PortalKit
import UIKit

/// VoiceMessageRecorder records one voice message while a finger is held on the microphone bar: AAC in an m4a file,
/// mono, 44.1 kHz, about 64 kbps. It meters the sound while it records, and the 48 bars and the length of the message are
/// worked out from that, on the phone.
@MainActor
@Observable
final class VoiceMessageRecorder {
    /// What starting a recording came to.
    enum StartResult: Equatable {
        case started
        /// The first press asked for the microphone and nothing was recorded.
        case askedForPermission
        case denied
        case failed
    }

    /// What a finished recording came to.
    enum Outcome {
        case recording(VoiceRecording)
        case tooShort
        case cancelled
    }

    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    /// Whether the finger is far enough up that letting go cancels.
    private(set) var isCancelling = false
    /// The heights of the latest readings, for the live meter.
    private(set) var liveAmplitudes: [Float] = []

    /// Called when the recording reaches its limit and must be sent now.
    var onLimitReached: (() -> Void)?

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var amplitudes: [Float] = []
    private var meterTask: Task<Void, Never>?

    static let meterInterval: TimeInterval = 0.05
    private static let liveAmplitudeCount = 36

    /// The remaining seconds once the countdown shows.
    var countdownSecondsLeft: Int? { VoiceMessageRules.countdownSecondsLeft(elapsed: elapsed) }

    func begin() async -> StartResult {
        guard !isRecording else { return .failed }
        let microphone = AVAudioApplication.shared.recordPermission
        if microphone == .undetermined {
            _ = await AVAudioApplication.requestRecordPermission()
            return .askedForPermission
        }
        guard microphone == .granted else { return .denied }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: VoiceMessageRules.sampleRateHertz,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: VoiceMessageRules.bitRate,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let created = try AVAudioRecorder(url: url, settings: settings)
            created.isMeteringEnabled = true
            guard created.record() else { return .failed }
            recorder = created
            fileURL = url
            amplitudes = []
            liveAmplitudes = []
            elapsed = 0
            isCancelling = false
            isRecording = true
            startMetering()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            return .started
        } catch {
            return .failed
        }
    }

    /// Follows the finger: `upward` is how far above where it went down, in points.
    func follow(upward: Double) {
        guard isRecording else { return }
        let cancelling = VoiceMessageRules.isCancelling(upward: upward)
        if cancelling != isCancelling {
            isCancelling = cancelling
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    /// Ends the recording. A cancelled or too short one is deleted.
    func finish(cancel: Bool) -> Outcome {
        guard isRecording, let recorder, let fileURL else { return .cancelled }
        let length = max(elapsed, recorder.currentTime)
        recorder.stop()
        meterTask?.cancel()
        meterTask = nil
        isRecording = false
        isCancelling = false
        self.recorder = nil
        self.fileURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if cancel {
            try? FileManager.default.removeItem(at: fileURL)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return .cancelled
        }
        if VoiceMessageRules.isTooShort(length) {
            try? FileManager.default.removeItem(at: fileURL)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return .tooShort
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let levels = VoiceMessageRules.levels(fromAmplitudes: amplitudes)
        return .recording(VoiceRecording(fileURL: fileURL, durationMS: Int((min(length, VoiceMessageRules.maximumDuration) * 1000).rounded()), levels: levels))
    }

    private func startMetering() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.meterInterval * 1_000_000_000))
                guard let self, self.isRecording, let recorder = self.recorder else { return }
                recorder.updateMeters()
                let amplitude = VoiceMessageRules.amplitude(decibels: recorder.averagePower(forChannel: 0))
                self.amplitudes.append(amplitude)
                self.liveAmplitudes.append(amplitude)
                if self.liveAmplitudes.count > Self.liveAmplitudeCount { self.liveAmplitudes.removeFirst(self.liveAmplitudes.count - Self.liveAmplitudeCount) }
                self.elapsed = recorder.currentTime
                if VoiceMessageRules.isAtLimit(self.elapsed) {
                    self.onLimitReached?()
                    return
                }
            }
        }
    }
}

/// VoiceRecording is a finished recording, ready to upload.
struct VoiceRecording: Equatable {
    let fileURL: URL
    let durationMS: Int
    let levels: [Int]
}
