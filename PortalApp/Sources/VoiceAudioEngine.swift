import AVFoundation
import Foundation
import PortalKit

/// LinearResampler turns the microphone's samples into 24 kHz ones. It keeps
/// the fractional position between buffers so nothing clicks at the joins.
final class LinearResampler {
    private let step: Double
    private var held: [Float] = []
    private var position = 0.0

    init(inputRate: Double, outputRate: Double = Double(VoiceAudio.sampleRateHertz)) {
        step = inputRate / outputRate
    }

    func process(_ input: [Float]) -> [Float] {
        held.append(contentsOf: input)
        var output: [Float] = []
        output.reserveCapacity(Int(Double(input.count) / step) + 2)
        while Int(position) + 1 < held.count {
            let index = Int(position)
            let fraction = Float(position - Double(index))
            output.append(held[index] * (1 - fraction) + held[index + 1] * fraction)
            position += step
        }
        let consumed = min(Int(position), held.count)
        if consumed > 0 {
            held.removeFirst(consumed)
            position -= Double(consumed)
        }
        return output
    }
}

/// VoiceAudioEngine is the call's audio: the microphone through the system's
/// voice processing (echo cancellation and noise suppression), cut into the
/// 100 ms frames the socket takes, and a player for the answer's audio.
final class VoiceAudioEngine: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let playbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(VoiceAudio.sampleRateHertz), channels: 1, interleaved: false)!
    private var resampler: LinearResampler?
    private var frameByteCount = VoiceAudio.bytesPerFrame
    private var pending = Data()
    private let lock = NSLock()
    private var epoch = 0
    private var isRunning = false

    /// Called on the audio thread with each 4,800-byte frame of 24 kHz 16-bit mono audio.
    var onFrame: (@Sendable (Data) -> Void)?

    /// Starts the microphone, cut into frames of `format`: a call uses the standard one, and dictation the one its socket names.
    func start(format: DictationFormat = .standard) throws {
        frameByteCount = format.bytesPerFrame
        pending = Data()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
        let input = engine.inputNode
        // Voice processing must be on before the formats are read.
        try input.setVoiceProcessingEnabled(true)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else { throw VoiceAudioError.noMicrophone }
        resampler = LinearResampler(inputRate: inputFormat.sampleRate, outputRate: Double(format.sampleRateHertz))
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        engine.prepare()
        try engine.start()
        player.play()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        engine.inputNode.removeTap(onBus: 0)
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0], let resampler else { return }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        let converted = resampler.process(samples)
        var bytes = Data(capacity: converted.count * 2)
        for sample in converted {
            let clamped = max(-1, min(1, sample))
            let value = Int16(clamped * 32_767)
            bytes.append(UInt8(truncatingIfNeeded: value))
            bytes.append(UInt8(truncatingIfNeeded: value >> 8))
        }
        pending.append(bytes)
        while pending.count >= frameByteCount {
            let frame = pending.prefix(frameByteCount)
            pending.removeFirst(frameByteCount)
            onFrame?(Data(frame))
        }
    }

    // MARK: playback

    /// Queues 24 kHz 16-bit audio to play. `played` is told how many samples
    /// were actually played, unless playback was cut off first.
    func play(pcm: Data, played: @escaping @Sendable (Int) -> Void) {
        let frames = pcm.count / VoiceAudio.bytesPerSample
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(frames)) else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        let destination = buffer.floatChannelData![0]
        pcm.withUnsafeBytes { raw in
            for index in 0..<frames {
                let low = UInt16(raw[index * 2])
                let high = UInt16(raw[index * 2 + 1])
                destination[index] = Float(Int16(bitPattern: low | (high << 8))) / 32_768
            }
        }
        schedule(buffer, frames: frames, played: played)
    }

    /// Queues decoded audio of any format the system reads (the older path's spoken answers).
    func play(file url: URL, played: @escaping @Sendable (Int) -> Void) throws {
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { return }
        try file.read(into: buffer)
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
        schedule(buffer, frames: Int(buffer.frameLength), played: played)
    }

    private func schedule(_ buffer: AVAudioPCMBuffer, frames: Int, played: @escaping @Sendable (Int) -> Void) {
        lock.lock()
        let scheduledEpoch = epoch
        lock.unlock()
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            let isCurrent = self.epoch == scheduledEpoch
            self.lock.unlock()
            if isCurrent { played(frames) }
        }
        if !player.isPlaying { player.play() }
    }

    /// Lowers the answer's volume at once, when the person starts to speak.
    func duck() { player.volume = 0.25 }

    func restoreVolume() { player.volume = 1 }

    func pause() { player.pause() }

    func resume() {
        player.volume = 1
        player.play()
    }

    /// Drops everything queued and playing. What was cut off reports nothing.
    func flushPlayback() {
        lock.lock()
        epoch += 1
        lock.unlock()
        player.stop()
        player.volume = 1
        player.play()
    }
}

enum VoiceAudioError: Error {
    case noMicrophone
}
