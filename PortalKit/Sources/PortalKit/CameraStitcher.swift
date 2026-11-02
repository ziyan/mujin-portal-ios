import Foundation

/// CameraDisplaySample is a video frame placed on the one time axis a stream
/// plays on, ready to become a sample buffer.
public struct CameraDisplaySample: Equatable, Sendable {
    public let data: Data
    public let presentationTicks: Int64
    /// Nil when the frames are not reordered, so the decoder is told no decode time.
    public let decodeTicks: Int64?
    public let durationTicks: Int64
    public let isSync: Bool
    /// False for a frame that is only there for the frames after it to be decoded: the start of a window repeats the frames
    /// since the key frame before it, and those were shown by the window before.
    public let isDisplayed: Bool
}

/// CameraAudioSample is an AAC frame placed on the same time axis as the video, in the audio track's own ticks.
public struct CameraAudioSample: Equatable, Sendable {
    public let data: Data
    public let presentationTicks: Int64
    public let durationTicks: Int64
}

/// CameraStitchedFragment is what one fragment adds to the stream.
public struct CameraStitchedFragment: Equatable, Sendable {
    public let video: [CameraDisplaySample]
    public let audio: [CameraAudioSample]
}

/// CameraStitcher puts the fragments of one stream on a single time axis.
///
/// The NVR stamps each fragment's `tfdt` with the wall clock, so the stamp
/// divided by the timescale is the moment the picture was recorded. That is
/// used as it is (absolute mode) when the first fragment is near the moment
/// that was asked for; a stream whose stamps are something else is laid end to
/// end from the asked-for moment (sequence mode), the way the web player does,
/// and the clock it shows is then approximate.
public struct CameraStitcher: Sendable {
    public enum Mode: Equatable, Sendable {
        case undecided
        case absolute
        case sequence
    }

    /// How far the first fragment's stamp may be from the moment asked for and still count as a wall clock.
    public static let toleranceMS: Double = 10 * 60_000

    public let configuration: CameraVideoConfiguration
    /// The audio track, or nil when sound is not wanted or the camera has none.
    public let audio: CameraAudioConfiguration?
    public let expectedEpochMS: Double
    public private(set) var mode = Mode.undecided
    /// The moment the first fragment's stamp names, as milliseconds since 1970, whether or not it was taken for a wall clock.
    public private(set) var firstFragmentEpochMS: Double?

    private var sequenceAnchorTicks: Int64 = 0
    private var nextSequenceTicks: Int64 = 0
    private var latestDisplayedEndTicks: Int64?
    private var repeatedBeforeTicks: Int64?
    /// How far the video of the latest fragment was moved on the axis, in video ticks; the audio of a fragment is moved by the same time.
    private var shiftTicks: Int64 = 0

    public init(configuration: CameraVideoConfiguration, audio: CameraAudioConfiguration? = nil, expectedEpochMS: Double) {
        self.configuration = configuration
        self.audio = audio
        self.expectedEpochMS = expectedEpochMS
    }

    public var timescale: Int64 { Int64(configuration.timescale) }

    /// Seconds on the stream's time axis for a wall-clock moment.
    public func axisSeconds(forEpochMS epochMS: Double) -> Double {
        switch mode {
        case .absolute, .undecided:
            return epochMS / 1000
        case .sequence:
            return Double(sequenceAnchorTicks) / Double(timescale) + (epochMS - expectedEpochMS) / 1000
        }
    }

    /// The wall-clock moment for a point on the stream's time axis.
    public func epochMS(forAxisSeconds seconds: Double) -> Double {
        switch mode {
        case .absolute, .undecided:
            return seconds * 1000
        case .sequence:
            return expectedEpochMS + (seconds - Double(sequenceAnchorTicks) / Double(timescale)) * 1000
        }
    }

    /// Call when a new window's socket starts. Its first frames repeat the key frame's group from the end of the window before, and
    /// those that were already shown are marked not to be shown again.
    public mutating func beginWindow() {
        repeatedBeforeTicks = latestDisplayedEndTicks
    }

    /// Places a fragment's video frames on the axis. Fragments with no video give nothing.
    public mutating func stitch(_ fragment: Data) -> [CameraDisplaySample] {
        stitchAll(fragment).video
    }

    /// Places a fragment's video frames and, when the stream has a wanted audio track, its audio frames on the axis.
    public mutating func stitchAll(_ fragment: Data) -> CameraStitchedFragment {
        let tracks = CameraMP4.parseFragment(fragment)
        var output: [CameraDisplaySample] = []
        for track in tracks where track.trackId == configuration.trackId && !track.samples.isEmpty {
            if mode == .undecided { decideMode(firstBaseTicks: track.baseMediaDecodeTime) }
            let shift: Int64
            switch mode {
            case .absolute, .undecided:
                shift = 0
            case .sequence:
                shift = nextSequenceTicks - Int64(track.baseMediaDecodeTime)
            }
            shiftTicks = shift
            let isReordered = track.samples.contains { $0.compositionOffsetTicks != 0 }
            for sample in track.samples {
                let presentation = sample.presentationTicks + shift
                // A repeated stretch is recognized by its time, so it can only be told in absolute mode, where the time is the camera's.
                // The limit is the one the window started with: frames shown out of order inside a window are not repeats of each other.
                let isDisplayed = mode == .sequence || repeatedBeforeTicks.map { presentation >= $0 - sample.durationTicks / 2 } ?? true
                if isDisplayed { latestDisplayedEndTicks = max(latestDisplayedEndTicks ?? .min, presentation + sample.durationTicks) }
                output.append(
                    CameraDisplaySample(
                        data: sample.data, presentationTicks: presentation, decodeTicks: isReordered ? sample.decodeTicks + shift : nil,
                        durationTicks: sample.durationTicks, isSync: sample.isSync, isDisplayed: isDisplayed))
            }
            if mode == .sequence {
                nextSequenceTicks += track.durationTicks ?? track.samples.reduce(0) { $0 + $1.durationTicks }
            }
        }
        return CameraStitchedFragment(video: output, audio: stitchAudio(tracks))
    }

    /// The audio frames of a fragment, moved by the time the video was moved by, and without the ones a window repeats.
    private func stitchAudio(_ tracks: [CameraTrackFragment]) -> [CameraAudioSample] {
        guard let audio else { return [] }
        let videoSeconds = Double(timescale)
        let shiftSeconds = Double(shiftTicks) / videoSeconds
        let audioShift = Int64((shiftSeconds * Double(audio.timescale)).rounded())
        var output: [CameraAudioSample] = []
        for track in tracks where track.trackId == audio.trackId {
            for sample in track.samples {
                let presentation = sample.presentationTicks + audioShift
                if mode == .absolute, let repeatedBeforeTicks {
                    let seconds = Double(presentation) / Double(audio.timescale)
                    let halfDuration = Double(sample.durationTicks) / Double(audio.timescale) / 2
                    if seconds < Double(repeatedBeforeTicks) / videoSeconds - halfDuration { continue }
                }
                output.append(CameraAudioSample(data: sample.data, presentationTicks: presentation, durationTicks: sample.durationTicks))
            }
        }
        return output
    }

    private mutating func decideMode(firstBaseTicks: UInt64) {
        let epochMS = Double(firstBaseTicks) / Double(timescale) * 1000
        firstFragmentEpochMS = epochMS
        if abs(epochMS - expectedEpochMS) <= Self.toleranceMS {
            mode = .absolute
        } else {
            mode = .sequence
            sequenceAnchorTicks = Int64(expectedEpochMS / 1000 * Double(timescale))
            nextSequenceTicks = sequenceAnchorTicks
        }
    }
}

/// CameraLiveSync decides when the clock of a live picture is moved. Frames
/// are shown a little after they arrive, so a burst does not play fast and a
/// late frame does not stall the rest.
public enum CameraLiveSync {
    /// How long before a frame's time the clock is set when it is moved.
    public static let cushionSeconds = 0.6
    /// How far ahead of the clock a frame may be before the picture is considered to lag and is brought forward.
    public static let maximumLeadSeconds = 3.0

    /// Where to move the clock to, or nil to leave it. `leadSeconds` is how far the newest fragment's first frame is ahead of the clock.
    public static func rebasedSeconds(leadSeconds: Double, firstFrameSeconds: Double) -> Double? {
        guard leadSeconds < 0 || leadSeconds > maximumLeadSeconds else { return nil }
        return firstFrameSeconds - cushionSeconds
    }
}
