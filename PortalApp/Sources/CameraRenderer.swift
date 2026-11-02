import AVFoundation
import AudioToolbox
import CoreMedia
import PortalKit
import SwiftUI
import UIKit

/// CameraDisplayView is a view whose layer shows decoded camera frames.
final class CameraDisplayView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        displayLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) { nil }
}

/// CameraRenderer turns the frames of a stream into sample buffers, hands
/// them to the system's hardware decoder through the display layer, and keeps
/// the layer's clock. The clock's time is the stream's time axis, so pausing
/// is a rate of zero and a speed is a rate.
///
/// Sound is off until asked for. While it is off the audio frames are only
/// kept (everything ahead of the clock, which is small next to the video), nothing is handed to the system and the audio
/// session is not touched, so music playing on the phone is not interrupted.
/// Turned on, the audio renderer follows the same clock through a
/// synchronizer.
@MainActor
final class CameraRenderer {
    let view = CameraDisplayView()

    private var formatDescription: CMVideoFormatDescription?
    private var timebase: CMTimebase?
    private var timescale: CMTimeScale = 90_000
    private var pending: [CMSampleBuffer] = []
    private var isRequestingData = false

    private let synchronizer = AVSampleBufferRenderSynchronizer()
    private let audioRenderer = AVSampleBufferAudioRenderer()
    private var audioConfiguration: CameraAudioConfiguration?
    private var audioFormatDescription: CMAudioFormatDescription?
    /// Audio waiting for the audio renderer, with the stream time at which each ends.
    private var pendingAudio: [(buffer: CMSampleBuffer, endSeconds: Double)] = []
    private var isRequestingAudio = false
    private var currentRate = 0.0
    private(set) var isSoundOn = false

    /// How far behind the clock audio is kept while sound is off, so that turning sound on finds what plays next.
    private static let keptAudioSeconds = 1.0
    /// The system plays audio between these speeds; outside them it is too garbled to be worth hearing.
    private static let audibleRates = 0.5...2.0

    /// Frames waiting for the layer to take them; the player keeps this small by not asking the NVR for more while it is large.
    var pendingCount: Int { pending.count }

    /// The time on the stream's axis the clock is at, in seconds.
    var clockSeconds: Double {
        guard let timebase else { return 0 }
        return CMTimebaseGetTime(timebase).seconds
    }

    var rate: Double {
        guard let timebase else { return 0 }
        return CMTimebaseGetRate(timebase)
    }

    /// Prepares for a stream's frames. Fails when the decoder cannot be set up from the parameter sets.
    func configure(_ configuration: CameraVideoConfiguration) -> Bool {
        timescale = CMTimeScale(configuration.timescale)
        formatDescription = Self.makeFormatDescription(configuration)
        guard formatDescription != nil else { return false }
        if timebase == nil {
            var created: CMTimebase?
            CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &created)
            timebase = created
            if let created { view.displayLayer.controlTimebase = created }
        }
        if let timebase { CMTimebaseSetRate(timebase, rate: 0) }
        return true
    }

    func setClock(seconds: Double, rate: Double) {
        guard let timebase else { return }
        CMTimebaseSetTime(timebase, time: CMTime(seconds: seconds, preferredTimescale: 90_000))
        CMTimebaseSetRate(timebase, rate: rate)
        currentRate = rate
        followClockWithSound()
    }

    func setRate(_ rate: Double) {
        guard let timebase else { return }
        CMTimebaseSetRate(timebase, rate: rate)
        currentRate = rate
        followClockWithSound()
    }

    func enqueue(_ samples: [CameraDisplaySample]) {
        for sample in samples {
            if let buffer = makeSampleBuffer(sample) { pending.append(buffer) }
        }
        feed()
        startRequestingDataIfNeeded()
    }

    /// Drops everything shown and queued: a seek, or a stream that starts over.
    func reset(removingImage: Bool) {
        pending.removeAll()
        let renderer = view.displayLayer.sampleBufferRenderer
        renderer.stopRequestingMediaData()
        isRequestingData = false
        if removingImage {
            view.displayLayer.flushAndRemoveImage()
        } else {
            view.displayLayer.flush()
        }
        if let timebase { CMTimebaseSetRate(timebase, rate: 0) }
        currentRate = 0
        pendingAudio.removeAll()
        audioRenderer.stopRequestingMediaData()
        isRequestingAudio = false
        audioRenderer.flush()
        if isSoundOn { synchronizer.rate = 0 }
    }

    private func startRequestingDataIfNeeded() {
        guard !isRequestingData, !pending.isEmpty else { return }
        isRequestingData = true
        view.displayLayer.sampleBufferRenderer.requestMediaDataWhenReady(on: DispatchQueue.main) { [weak self] in
            MainActor.assumeIsolated { self?.feed() }
        }
    }

    private func feed() {
        let renderer = view.displayLayer.sampleBufferRenderer
        if renderer.status == .failed {
            // A failed layer (the decoder was lost, as when the app was in the background) takes nothing until it is flushed.
            view.displayLayer.flush()
        }
        while renderer.isReadyForMoreMediaData, !pending.isEmpty {
            renderer.enqueue(pending.removeFirst())
        }
        if pending.isEmpty, isRequestingData {
            renderer.stopRequestingMediaData()
            isRequestingData = false
        }
    }

    // MARK: sound

    /// Prepares for a stream's audio track, or for a stream without one (nil).
    func configureAudio(_ configuration: CameraAudioConfiguration?) {
        audioConfiguration = configuration
        audioFormatDescription = configuration.flatMap(Self.makeAudioFormatDescription)
        pendingAudio.removeAll()
    }

    /// Whether the stream's sound can be played at all.
    var canPlaySound: Bool { audioFormatDescription != nil }

    func enqueueAudio(_ samples: [CameraAudioSample]) {
        guard let audioConfiguration, let buffer = makeAudioSampleBuffer(samples, configuration: audioConfiguration), let last = samples.last else { return }
        let endSeconds = Double(last.presentationTicks + last.durationTicks) / Double(audioConfiguration.timescale)
        pendingAudio.append((buffer, endSeconds))
        if !isSoundOn {
            let oldest = clockSeconds - Self.keptAudioSeconds
            pendingAudio.removeAll { $0.endSeconds < oldest }
            return
        }
        feedAudio()
        startRequestingAudioIfNeeded()
    }

    /// Turns sound on or off. On, the audio session plays over other audio; off, it is let go so that other audio resumes.
    func setSound(on isOn: Bool) {
        guard isOn != isSoundOn else { return }
        isSoundOn = isOn
        let session = AVAudioSession.sharedInstance()
        if isOn {
            try? session.setCategory(.playback, mode: .moviePlayback)
            try? session.setActive(true)
            if synchronizer.renderers.isEmpty { synchronizer.addRenderer(audioRenderer) }
            audioRenderer.audioTimePitchAlgorithm = .timeDomain
            audioRenderer.flush()
            followClockWithSound()
            feedAudio()
            startRequestingAudioIfNeeded()
        } else {
            audioRenderer.stopRequestingMediaData()
            isRequestingAudio = false
            audioRenderer.flush()
            synchronizer.rate = 0
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// Moves the audio renderer's clock to where the video's is, at the same rate.
    private func followClockWithSound() {
        guard isSoundOn, let timebase else { return }
        audioRenderer.isMuted = !Self.audibleRates.contains(currentRate)
        synchronizer.setRate(Float(currentRate), time: CMTimebaseGetTime(timebase))
    }

    private func startRequestingAudioIfNeeded() {
        guard isSoundOn, !isRequestingAudio, !pendingAudio.isEmpty else { return }
        isRequestingAudio = true
        audioRenderer.requestMediaDataWhenReady(on: DispatchQueue.main) { [weak self] in
            MainActor.assumeIsolated { self?.feedAudio() }
        }
    }

    private func feedAudio() {
        guard isSoundOn else { return }
        if audioRenderer.status == .failed { audioRenderer.flush() }
        // Audio that ended before the clock is not worth the system's time.
        let oldest = clockSeconds - 0.2
        pendingAudio.removeAll { $0.endSeconds < oldest }
        while audioRenderer.isReadyForMoreMediaData, !pendingAudio.isEmpty {
            audioRenderer.enqueue(pendingAudio.removeFirst().buffer)
        }
        if pendingAudio.isEmpty, isRequestingAudio {
            audioRenderer.stopRequestingMediaData()
            isRequestingAudio = false
        }
    }

    // MARK: building the pieces

    private static func makeAudioFormatDescription(_ configuration: CameraAudioConfiguration) -> CMAudioFormatDescription? {
        var description = AudioStreamBasicDescription(
            mSampleRate: configuration.sampleRate, mFormatID: kAudioFormatMPEG4AAC, mFormatFlags: 0, mBytesPerPacket: 0, mFramesPerPacket: 1024,
            mBytesPerFrame: 0, mChannelsPerFrame: UInt32(configuration.channelCount), mBitsPerChannel: 0, mReserved: 0)
        var format: CMAudioFormatDescription?
        let status = configuration.magicCookie.withUnsafeBytes { cookie in
            CMAudioFormatDescriptionCreate(
                allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: cookie.count,
                magicCookie: cookie.baseAddress, extensions: nil, formatDescriptionOut: &format)
        }
        return status == noErr ? format : nil
    }

    /// One sample buffer for a run of AAC frames that follow each other, with the size of each as its packet description.
    private func makeAudioSampleBuffer(_ samples: [CameraAudioSample], configuration: CameraAudioConfiguration) -> CMSampleBuffer? {
        guard let audioFormatDescription, let first = samples.first else { return nil }
        let total = samples.reduce(0) { $0 + $1.data.count }
        guard total > 0 else { return nil }
        var block: CMBlockBuffer?
        guard
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: total, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
                offsetToData: 0, dataLength: total, flags: 0, blockBufferOut: &block) == kCMBlockBufferNoErr, let block
        else { return nil }
        var offset = 0
        var packets: [AudioStreamPacketDescription] = []
        for sample in samples {
            let status = sample.data.withUnsafeBytes { bytes -> OSStatus in
                guard let base = bytes.baseAddress else { return -1 }
                return CMBlockBufferReplaceDataBytes(with: base, blockBuffer: block, offsetIntoDestination: offset, dataLength: sample.data.count)
            }
            guard status == kCMBlockBufferNoErr else { return nil }
            packets.append(AudioStreamPacketDescription(mStartOffset: Int64(offset), mVariableFramesInPacket: 0, mDataByteSize: UInt32(sample.data.count)))
            offset += sample.data.count
        }
        var buffer: CMSampleBuffer?
        let status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: audioFormatDescription, sampleCount: samples.count,
            presentationTimeStamp: CMTime(value: first.presentationTicks, timescale: CMTimeScale(configuration.timescale)), packetDescriptions: packets,
            sampleBufferOut: &buffer)
        return status == noErr ? buffer : nil
    }

    private static func makeFormatDescription(_ configuration: CameraVideoConfiguration) -> CMVideoFormatDescription? {
        let sets = configuration.parameterSets
        guard !sets.isEmpty else { return nil }
        let pointers = sets.map { data -> UnsafeMutablePointer<UInt8> in
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: max(data.count, 1))
            data.copyBytes(to: buffer, count: data.count)
            return buffer
        }
        defer { pointers.forEach { $0.deallocate() } }
        let constantPointers: [UnsafePointer<UInt8>] = pointers.map { UnsafePointer($0) }
        let sizes = sets.map { $0.count }
        var format: CMFormatDescription?
        let status: OSStatus
        switch configuration.codec {
        case .h264:
            status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                allocator: kCFAllocatorDefault, parameterSetCount: sets.count, parameterSetPointers: constantPointers, parameterSetSizes: sizes,
                nalUnitHeaderLength: Int32(configuration.nalLengthSize), formatDescriptionOut: &format)
        case .h265:
            status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                allocator: kCFAllocatorDefault, parameterSetCount: sets.count, parameterSetPointers: constantPointers, parameterSetSizes: sizes,
                nalUnitHeaderLength: Int32(configuration.nalLengthSize), extensions: nil, formatDescriptionOut: &format)
        }
        return status == noErr ? format : nil
    }

    private func makeSampleBuffer(_ sample: CameraDisplaySample) -> CMSampleBuffer? {
        guard let formatDescription, !sample.data.isEmpty else { return nil }
        let count = sample.data.count
        var block: CMBlockBuffer?
        guard
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: count, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
                offsetToData: 0, dataLength: count, flags: 0, blockBufferOut: &block) == kCMBlockBufferNoErr, let block
        else { return nil }
        let copied = sample.data.withUnsafeBytes { bytes -> OSStatus in
            guard let base = bytes.baseAddress else { return -1 }
            return CMBlockBufferReplaceDataBytes(with: base, blockBuffer: block, offsetIntoDestination: 0, dataLength: count)
        }
        guard copied == kCMBlockBufferNoErr else { return nil }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: sample.durationTicks, timescale: timescale), presentationTimeStamp: CMTime(value: sample.presentationTicks, timescale: timescale),
            decodeTimeStamp: sample.decodeTicks.map { CMTime(value: $0, timescale: timescale) } ?? .invalid)
        var size = count
        var buffer: CMSampleBuffer?
        guard
            CMSampleBufferCreateReady(
                allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: formatDescription, sampleCount: 1, sampleTimingEntryCount: 1,
                sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &buffer) == noErr, let buffer
        else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: true), CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            if !sample.isSync {
                CFDictionarySetValue(dictionary, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
            }
            if !sample.isDisplayed {
                CFDictionarySetValue(dictionary, Unmanaged.passUnretained(kCMSampleAttachmentKey_DoNotDisplay).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
            }
        }
        return buffer
    }
}

/// CameraSurface puts a renderer's view in SwiftUI.
struct CameraSurface: UIViewRepresentable {
    let renderer: CameraRenderer

    func makeUIView(context: Context) -> CameraDisplayView { renderer.view }

    func updateUIView(_ view: CameraDisplayView, context: Context) {}
}
