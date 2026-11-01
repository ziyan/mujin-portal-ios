import AVFoundation
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
@MainActor
final class CameraRenderer {
    let view = CameraDisplayView()

    private var formatDescription: CMVideoFormatDescription?
    private var timebase: CMTimebase?
    private var timescale: CMTimeScale = 90_000
    private var pending: [CMSampleBuffer] = []
    private var isRequestingData = false

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
    }

    func setRate(_ rate: Double) {
        guard let timebase else { return }
        CMTimebaseSetRate(timebase, rate: rate)
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

    // MARK: building the pieces

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
