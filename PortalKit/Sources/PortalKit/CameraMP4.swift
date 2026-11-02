import Foundation

/// CameraVideoCodec is the codec of a camera's video track.
public enum CameraVideoCodec: Equatable, Sendable {
    case h264
    case h265
}

/// CameraVideoConfiguration is what a decoder needs to know about the video
/// track, read from the initialization segment: the codec, the picture size,
/// how many bytes each sample's NAL unit lengths take, and the parameter sets
/// (H.264: sequence then picture parameter sets; H.265: video, sequence then
/// picture parameter sets).
public struct CameraVideoConfiguration: Equatable, Sendable {
    public let trackId: UInt32
    public let timescale: UInt32
    public let codec: CameraVideoCodec
    public let width: Int
    public let height: Int
    public let nalLengthSize: Int
    public let parameterSets: [Data]

    public init(trackId: UInt32, timescale: UInt32, codec: CameraVideoCodec, width: Int, height: Int, nalLengthSize: Int, parameterSets: [Data]) {
        self.trackId = trackId
        self.timescale = timescale
        self.codec = codec
        self.width = width
        self.height = height
        self.nalLengthSize = nalLengthSize
        self.parameterSets = parameterSets
    }
}

/// CameraAudioConfiguration is what a decoder needs to know about an AAC audio track, read from the initialization segment.
public struct CameraAudioConfiguration: Equatable, Sendable {
    public let trackId: UInt32
    public let timescale: UInt32
    public let sampleRate: Double
    public let channelCount: Int
    /// The `esds` box's descriptors, which is the codec's own configuration as an AAC decoder takes it.
    public let magicCookie: Data

    public init(trackId: UInt32, timescale: UInt32, sampleRate: Double, channelCount: Int, magicCookie: Data) {
        self.trackId = trackId
        self.timescale = timescale
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.magicCookie = magicCookie
    }
}

/// CameraInitSegment is the part of the initialization segment the app uses.
public struct CameraInitSegment: Equatable, Sendable {
    /// Every track's timescale (ticks per second) by track id. A camera with audio has two, and they differ.
    public let timescales: [UInt32: UInt32]
    public let video: CameraVideoConfiguration?
    public let hasAudio: Bool
    /// The AAC audio track, or nil when the camera has none or its audio is another codec.
    public let audio: CameraAudioConfiguration?
}

public enum CameraMP4Error: Error, Equatable, Sendable {
    case noMovieBox
    case noVideoTrack
    case unsupportedCodec(String)
    case malformedConfiguration
}

/// CameraSample is one video frame of a fragment, still as the camera encoded it.
public struct CameraSample: Equatable, Sendable {
    /// The frame's NAL units, each behind a length of `nalLengthSize` bytes, as an MP4 stores them.
    public let data: Data
    /// The frame's decode time in the track's ticks.
    public let decodeTicks: Int64
    public let durationTicks: Int64
    /// How far the presentation time is after the decode time, for streams with reordered frames.
    public let compositionOffsetTicks: Int64
    public let isSync: Bool

    public var presentationTicks: Int64 { decodeTicks + compositionOffsetTicks }

    public init(data: Data, decodeTicks: Int64, durationTicks: Int64, compositionOffsetTicks: Int64, isSync: Bool) {
        self.data = data
        self.decodeTicks = decodeTicks
        self.durationTicks = durationTicks
        self.compositionOffsetTicks = compositionOffsetTicks
        self.isSync = isSync
    }
}

/// CameraTrackFragment is one track's part of a fragment.
public struct CameraTrackFragment: Equatable, Sendable {
    public let trackId: UInt32
    /// The `tfdt` time. The NVR stamps it with the wall clock, so divided by the timescale it is seconds since 1970.
    public let baseMediaDecodeTime: UInt64
    public let samples: [CameraSample]
    /// Nil when neither the `trun` boxes nor `tfhd` say how long the samples last.
    public let durationTicks: Int64?
}

/// CameraMP4 reads the few boxes a live or recorded camera stream needs. It
/// does not read files: a fragment is a `moof` and its `mdat`, and the
/// initialization segment is a `moov`.
public enum CameraMP4 {
    struct Box {
        let type: String
        let start: Int
        let payloadStart: Int
        let end: Int
    }

    // MARK: boxes

    static func readUInt16(_ bytes: [UInt8], _ offset: Int) -> Int {
        (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
    }

    static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24) | (UInt32(bytes[offset + 1]) << 16) | (UInt32(bytes[offset + 2]) << 8) | UInt32(bytes[offset + 3])
    }

    static func readUInt64(_ bytes: [UInt8], _ offset: Int) -> UInt64 {
        (UInt64(readUInt32(bytes, offset)) << 32) | UInt64(readUInt32(bytes, offset + 4))
    }

    /// The boxes directly inside `start..<end`. A box that overruns the range ends the walk.
    static func boxes(_ bytes: [UInt8], from start: Int, to end: Int) -> [Box] {
        var result: [Box] = []
        var offset = start
        while offset + 8 <= end {
            var size = Int(readUInt32(bytes, offset))
            let type = String(decoding: bytes[(offset + 4)..<(offset + 8)], as: UTF8.self)
            var payloadStart = offset + 8
            if size == 1 {
                guard offset + 16 <= end else { break }
                let largeSize = readUInt64(bytes, offset + 8)
                guard largeSize <= UInt64(Int.max / 2) else { break }
                size = Int(largeSize)
                payloadStart = offset + 16
            } else if size == 0 {
                size = end - offset
            }
            guard size >= payloadStart - offset, offset + size <= end else { break }
            result.append(Box(type: type, start: offset, payloadStart: payloadStart, end: offset + size))
            offset += size
        }
        return result
    }

    static func firstBox(_ bytes: [UInt8], _ type: String, in parent: Box) -> Box? {
        boxes(bytes, from: parent.payloadStart, to: parent.end).first { $0.type == type }
    }

    static func allBoxes(_ bytes: [UInt8], _ type: String, in parent: Box) -> [Box] {
        boxes(bytes, from: parent.payloadStart, to: parent.end).filter { $0.type == type }
    }

    // MARK: the initialization segment

    /// Reads the tracks of an initialization segment.
    public static func parseInitSegment(_ data: Data) throws -> CameraInitSegment {
        let bytes = [UInt8](data)
        guard let moov = boxes(bytes, from: 0, to: bytes.count).first(where: { $0.type == "moov" }) else { throw CameraMP4Error.noMovieBox }
        var timescales: [UInt32: UInt32] = [:]
        var video: CameraVideoConfiguration?
        var videoError: CameraMP4Error?
        var hasAudio = false
        var audio: CameraAudioConfiguration?
        for trak in allBoxes(bytes, "trak", in: moov) {
            guard let tkhd = firstBox(bytes, "tkhd", in: trak), let mdia = firstBox(bytes, "mdia", in: trak),
                let mdhd = firstBox(bytes, "mdhd", in: mdia)
            else { continue }
            let trackIdOffset = tkhd.payloadStart + (bytes[tkhd.payloadStart] == 1 ? 20 : 12)
            let timescaleOffset = mdhd.payloadStart + (bytes[mdhd.payloadStart] == 1 ? 20 : 12)
            guard trackIdOffset + 4 <= tkhd.end, timescaleOffset + 4 <= mdhd.end else { continue }
            let trackId = readUInt32(bytes, trackIdOffset)
            let timescale = readUInt32(bytes, timescaleOffset)
            if timescale > 0 { timescales[trackId] = timescale }
            // hdlr: version and flags (4), predefined (4), then the handler type.
            let handler = firstBox(bytes, "hdlr", in: mdia).flatMap { handlerBox -> String? in
                guard handlerBox.payloadStart + 12 <= handlerBox.end else { return nil }
                return String(decoding: bytes[(handlerBox.payloadStart + 8)..<(handlerBox.payloadStart + 12)], as: UTF8.self)
            }
            if handler == "soun" {
                hasAudio = true
                if audio == nil { audio = parseAudioTrack(bytes, mdia: mdia, trackId: trackId, timescale: timescale) }
            }
            guard handler == "vide", video == nil, videoError == nil else { continue }
            do {
                video = try parseVideoTrack(bytes, mdia: mdia, trackId: trackId, timescale: timescale)
            } catch let error as CameraMP4Error {
                videoError = error
            }
        }
        if let videoError { throw videoError }
        return CameraInitSegment(timescales: timescales, video: video, hasAudio: hasAudio, audio: audio)
    }

    /// The sample entry of an AAC track: the `mp4a` entry, whose `esds` box holds the descriptors that name the codec and its settings.
    /// Returns nil for any other audio, which the app does not play.
    private static func parseAudioTrack(_ bytes: [UInt8], mdia: Box, trackId: UInt32, timescale: UInt32) -> CameraAudioConfiguration? {
        guard let minf = firstBox(bytes, "minf", in: mdia), let stbl = firstBox(bytes, "stbl", in: minf), let stsd = firstBox(bytes, "stsd", in: stbl),
            let entry = boxes(bytes, from: stsd.payloadStart + 8, to: stsd.end).first, entry.type == "mp4a",
            // An audio sample entry: six reserved bytes, the data reference index, eight bytes, the channel count, the sample size, four
            // bytes, then the sample rate as a 16.16 number.
            entry.payloadStart + 28 <= entry.end
        else { return nil }
        let channelCount = readUInt16(bytes, entry.payloadStart + 16)
        let entryRate = Double(readUInt16(bytes, entry.payloadStart + 24))
        guard let esds = boxes(bytes, from: entry.payloadStart + 28, to: entry.end).first(where: { $0.type == "esds" }), esds.payloadStart + 4 < esds.end
        else { return nil }
        let descriptors = Array(bytes[(esds.payloadStart + 4)..<esds.end])
        guard let specific = audioSpecificConfiguration(descriptors) else { return nil }
        let rate = specific.sampleRate ?? entryRate
        let channels = specific.channelCount ?? channelCount
        guard rate > 0, channels > 0 else { return nil }
        return CameraAudioConfiguration(trackId: trackId, timescale: timescale, sampleRate: rate, channelCount: channels, magicCookie: Data(descriptors))
    }

    private static let aacSampleRates: [Double] = [96_000, 88_200, 64_000, 48_000, 44_100, 32_000, 24_000, 22_050, 16_000, 12_000, 11_025, 8_000, 7_350]

    /// Walks the `esds` descriptors (ES, decoder configuration, decoder specific) and reads the AAC settings from the last one. Nil when the
    /// stream is not MPEG-4 audio, or the descriptors do not hold what an AAC decoder needs.
    static func audioSpecificConfiguration(_ descriptors: [UInt8]) -> (sampleRate: Double?, channelCount: Int?)? {
        var offset = 0
        func readLength() -> Int? {
            var length = 0
            for _ in 0..<4 {
                guard offset < descriptors.count else { return nil }
                let byte = Int(descriptors[offset])
                offset += 1
                length = (length << 7) | (byte & 0x7f)
                if byte & 0x80 == 0 { return length }
            }
            return nil
        }
        // ES_Descriptor: tag 3, then the ES id (2) and flags (1), with optional dependency, URL and OCR fields.
        guard offset < descriptors.count, descriptors[offset] == 0x03 else { return nil }
        offset += 1
        guard readLength() != nil, offset + 3 <= descriptors.count else { return nil }
        let flags = descriptors[offset + 2]
        offset += 3
        if flags & 0x80 != 0 { offset += 2 }
        if flags & 0x40 != 0 {
            guard offset < descriptors.count else { return nil }
            offset += 1 + Int(descriptors[offset])
        }
        if flags & 0x20 != 0 { offset += 2 }
        // DecoderConfigDescriptor: tag 4, the object type (0x40 is MPEG-4 audio), the stream type, the buffer size and two bit rates.
        guard offset < descriptors.count, descriptors[offset] == 0x04 else { return nil }
        offset += 1
        guard readLength() != nil, offset + 13 <= descriptors.count, descriptors[offset] == 0x40 else { return nil }
        offset += 13
        // DecoderSpecificInfo: tag 5, the AudioSpecificConfig.
        guard offset < descriptors.count, descriptors[offset] == 0x05 else { return nil }
        offset += 1
        guard let length = readLength(), length >= 2, offset + length <= descriptors.count else { return nil }
        let config = Array(descriptors[offset..<(offset + length)])
        var bitPosition = 0
        func readBits(_ count: Int) -> Int? {
            guard bitPosition + count <= config.count * 8 else { return nil }
            var value = 0
            for _ in 0..<count {
                value = (value << 1) | Int((config[bitPosition / 8] >> UInt8(7 - bitPosition % 8)) & 1)
                bitPosition += 1
            }
            return value
        }
        guard var objectType = readBits(5) else { return nil }
        if objectType == 31 {
            guard let extended = readBits(6) else { return nil }
            objectType = 32 + extended
        }
        // Only AAC is played: low complexity and its relatives, object types 1 to 4.
        guard (1...4).contains(objectType), let rateIndex = readBits(4) else { return nil }
        let sampleRate: Double?
        if rateIndex == 15 {
            sampleRate = readBits(24).map(Double.init)
        } else {
            sampleRate = rateIndex < aacSampleRates.count ? aacSampleRates[rateIndex] : nil
        }
        let channels = readBits(4)
        return (sampleRate, channels.flatMap { $0 > 0 && $0 <= 7 ? ($0 == 7 ? 8 : $0) : nil })
    }

    private static func parseVideoTrack(_ bytes: [UInt8], mdia: Box, trackId: UInt32, timescale: UInt32) throws -> CameraVideoConfiguration {
        guard let minf = firstBox(bytes, "minf", in: mdia), let stbl = firstBox(bytes, "stbl", in: minf), let stsd = firstBox(bytes, "stsd", in: stbl)
        else { throw CameraMP4Error.noVideoTrack }
        // stsd: version and flags (4), entry count (4), then the sample entries.
        let entries = boxes(bytes, from: stsd.payloadStart + 8, to: stsd.end)
        guard let entry = entries.first else { throw CameraMP4Error.noVideoTrack }
        // A visual sample entry: six reserved bytes, the data reference index, then 16 bytes before the size.
        guard entry.payloadStart + 28 <= entry.end else { throw CameraMP4Error.malformedConfiguration }
        let width = readUInt16(bytes, entry.payloadStart + 24)
        let height = readUInt16(bytes, entry.payloadStart + 26)
        let children = boxes(bytes, from: entry.payloadStart + 78, to: entry.end)
        switch entry.type {
        case "avc1", "avc3":
            guard let configuration = children.first(where: { $0.type == "avcC" }) else { throw CameraMP4Error.malformedConfiguration }
            let (nalLengthSize, sets) = try parseAVCConfiguration(bytes, configuration)
            return CameraVideoConfiguration(
                trackId: trackId, timescale: timescale, codec: .h264, width: width, height: height, nalLengthSize: nalLengthSize, parameterSets: sets)
        case "hvc1", "hev1":
            guard let configuration = children.first(where: { $0.type == "hvcC" }) else { throw CameraMP4Error.malformedConfiguration }
            let (nalLengthSize, sets) = try parseHEVCConfiguration(bytes, configuration)
            return CameraVideoConfiguration(
                trackId: trackId, timescale: timescale, codec: .h265, width: width, height: height, nalLengthSize: nalLengthSize, parameterSets: sets)
        default:
            throw CameraMP4Error.unsupportedCodec(entry.type)
        }
    }

    /// avcC: version, profile, compatibility, level, the NAL length size, then the sequence and picture parameter sets.
    private static func parseAVCConfiguration(_ bytes: [UInt8], _ box: Box) throws -> (Int, [Data]) {
        var offset = box.payloadStart
        guard offset + 7 <= box.end else { throw CameraMP4Error.malformedConfiguration }
        let nalLengthSize = Int(bytes[offset + 4] & 0x03) + 1
        let sequenceCount = Int(bytes[offset + 5] & 0x1f)
        offset += 6
        var sets: [Data] = []
        func readSet() throws {
            guard offset + 2 <= box.end else { throw CameraMP4Error.malformedConfiguration }
            let length = readUInt16(bytes, offset)
            offset += 2
            guard offset + length <= box.end else { throw CameraMP4Error.malformedConfiguration }
            sets.append(Data(bytes[offset..<(offset + length)]))
            offset += length
        }
        for _ in 0..<sequenceCount { try readSet() }
        guard offset < box.end else { throw CameraMP4Error.malformedConfiguration }
        let pictureCount = Int(bytes[offset])
        offset += 1
        for _ in 0..<pictureCount { try readSet() }
        guard sets.count >= 2 else { throw CameraMP4Error.malformedConfiguration }
        return (nalLengthSize, sets)
    }

    /// hvcC: 22 bytes of profile data ending in the NAL length size, then arrays of parameter sets by NAL unit type.
    private static func parseHEVCConfiguration(_ bytes: [UInt8], _ box: Box) throws -> (Int, [Data]) {
        var offset = box.payloadStart
        guard offset + 23 <= box.end else { throw CameraMP4Error.malformedConfiguration }
        let nalLengthSize = Int(bytes[offset + 21] & 0x03) + 1
        let arrayCount = Int(bytes[offset + 22])
        offset += 23
        var sets: [Data] = []
        for _ in 0..<arrayCount {
            guard offset + 3 <= box.end else { throw CameraMP4Error.malformedConfiguration }
            let unitType = Int(bytes[offset] & 0x3f)
            let unitCount = readUInt16(bytes, offset + 1)
            offset += 3
            for _ in 0..<unitCount {
                guard offset + 2 <= box.end else { throw CameraMP4Error.malformedConfiguration }
                let length = readUInt16(bytes, offset)
                offset += 2
                guard offset + length <= box.end else { throw CameraMP4Error.malformedConfiguration }
                // 32, 33 and 34 are the video, sequence and picture parameter sets. Other arrays (SEI) are not needed to decode.
                if (32...34).contains(unitType) { sets.append(Data(bytes[offset..<(offset + length)])) }
                offset += length
            }
        }
        guard sets.count >= 3 else { throw CameraMP4Error.malformedConfiguration }
        return (nalLengthSize, sets)
    }

    // MARK: fragments

    /// Reads every track fragment of a chunk of `moof` and `mdat` boxes, in order.
    public static func parseFragment(_ data: Data) -> [CameraTrackFragment] {
        let bytes = [UInt8](data)
        let top = boxes(bytes, from: 0, to: bytes.count)
        var result: [CameraTrackFragment] = []
        var index = 0
        while index < top.count {
            guard top[index].type == "moof" else {
                index += 1
                continue
            }
            let moof = top[index]
            // The media data of this movie fragment: the mdat boxes up to the next moof.
            var mdats: [Box] = []
            var next = index + 1
            while next < top.count, top[next].type != "moof" {
                if top[next].type == "mdat" { mdats.append(top[next]) }
                next += 1
            }
            result.append(contentsOf: parseMovieFragment(bytes, moof: moof, mdats: mdats))
            index = next
        }
        return result
    }

    private static func parseMovieFragment(_ bytes: [UInt8], moof: Box, mdats: [Box]) -> [CameraTrackFragment] {
        guard let firstMdat = mdats.first else { return [] }
        var result: [CameraTrackFragment] = []
        // Where a track fragment's samples begin when its trun does not say: after the previous track's.
        var cursor = firstMdat.payloadStart
        for traf in allBoxes(bytes, "traf", in: moof) {
            guard let tfhd = firstBox(bytes, "tfhd", in: traf), let tfdt = firstBox(bytes, "tfdt", in: traf), tfhd.payloadStart + 8 <= tfhd.end
            else { continue }
            let tfhdFlags = readUInt32(bytes, tfhd.payloadStart) & 0x00ff_ffff
            let trackId = readUInt32(bytes, tfhd.payloadStart + 4)
            var tfhdOffset = tfhd.payloadStart + 8
            var hasBaseDataOffset = false
            if tfhdFlags & 0x000001 != 0 {
                hasBaseDataOffset = true
                tfhdOffset += 8
            }
            if tfhdFlags & 0x000002 != 0 { tfhdOffset += 4 }
            var defaultDuration: Int64?
            var defaultSize: Int?
            var defaultFlags: UInt32?
            if tfhdFlags & 0x000008 != 0, tfhdOffset + 4 <= tfhd.end {
                defaultDuration = Int64(readUInt32(bytes, tfhdOffset))
                tfhdOffset += 4
            }
            if tfhdFlags & 0x000010 != 0, tfhdOffset + 4 <= tfhd.end {
                defaultSize = Int(readUInt32(bytes, tfhdOffset))
                tfhdOffset += 4
            }
            if tfhdFlags & 0x000020 != 0, tfhdOffset + 4 <= tfhd.end {
                defaultFlags = readUInt32(bytes, tfhdOffset)
                tfhdOffset += 4
            }

            let tfdtVersion = bytes[tfdt.payloadStart]
            let baseMediaDecodeTime: UInt64
            if tfdtVersion == 1 {
                guard tfdt.payloadStart + 12 <= tfdt.end else { continue }
                baseMediaDecodeTime = readUInt64(bytes, tfdt.payloadStart + 4)
            } else {
                guard tfdt.payloadStart + 8 <= tfdt.end else { continue }
                baseMediaDecodeTime = UInt64(readUInt32(bytes, tfdt.payloadStart + 4))
            }

            var samples: [CameraSample] = []
            var decodeTicks = Int64(baseMediaDecodeTime)
            var totalDuration: Int64? = 0
            var isReadable = true
            for trun in allBoxes(bytes, "trun", in: traf) {
                guard trun.payloadStart + 8 <= trun.end else {
                    isReadable = false
                    break
                }
                let trunVersion = bytes[trun.payloadStart]
                let trunFlags = readUInt32(bytes, trun.payloadStart) & 0x00ff_ffff
                let sampleCount = Int(readUInt32(bytes, trun.payloadStart + 4))
                var offset = trun.payloadStart + 8
                var dataOffset: Int?
                if trunFlags & 0x000001 != 0 {
                    guard offset + 4 <= trun.end else {
                        isReadable = false
                        break
                    }
                    dataOffset = Int(Int32(bitPattern: readUInt32(bytes, offset)))
                    offset += 4
                }
                var firstSampleFlags: UInt32?
                if trunFlags & 0x000004 != 0 {
                    guard offset + 4 <= trun.end else {
                        isReadable = false
                        break
                    }
                    firstSampleFlags = readUInt32(bytes, offset)
                    offset += 4
                }
                let perSample = (trunFlags & 0x100 != 0 ? 4 : 0) + (trunFlags & 0x200 != 0 ? 4 : 0) + (trunFlags & 0x400 != 0 ? 4 : 0) + (trunFlags & 0x800 != 0 ? 4 : 0)
                guard offset + sampleCount * perSample <= trun.end else {
                    isReadable = false
                    break
                }
                // The data offset counts from the start of the moof, as in every fragment this stream carries. A base data offset in the
                // tfhd names a position in a file that is not here, so such a fragment is read from where its media data begins.
                var position = cursor
                if let dataOffset, !hasBaseDataOffset {
                    position = moof.start + dataOffset
                }
                for sampleIndex in 0..<sampleCount {
                    var duration = defaultDuration
                    var size = defaultSize
                    var flags = defaultFlags
                    var compositionOffset: Int64 = 0
                    if trunFlags & 0x100 != 0 {
                        duration = Int64(readUInt32(bytes, offset))
                        offset += 4
                    }
                    if trunFlags & 0x200 != 0 {
                        size = Int(readUInt32(bytes, offset))
                        offset += 4
                    }
                    if trunFlags & 0x400 != 0 {
                        flags = readUInt32(bytes, offset)
                        offset += 4
                    }
                    if trunFlags & 0x800 != 0 {
                        let raw = readUInt32(bytes, offset)
                        compositionOffset = trunVersion == 0 ? Int64(raw) : Int64(Int32(bitPattern: raw))
                        offset += 4
                    }
                    if sampleIndex == 0, let firstSampleFlags { flags = firstSampleFlags }
                    guard let size, size >= 0, position >= 0, position + size <= bytes.count,
                        mdats.contains(where: { position >= $0.payloadStart && position + size <= $0.end })
                    else {
                        isReadable = false
                        break
                    }
                    let sampleData = Data(bytes[position..<(position + size)])
                    // Bit 16 of the sample flags marks a frame that depends on others. Without flags, the NAL units say.
                    let isSync = flags.map { $0 & 0x0001_0000 == 0 } ?? CameraNALUnits.containsKeyFrame(sampleData)
                    samples.append(
                        CameraSample(
                            data: sampleData, decodeTicks: decodeTicks, durationTicks: duration ?? 0, compositionOffsetTicks: compositionOffset, isSync: isSync))
                    if let duration, totalDuration != nil {
                        totalDuration = (totalDuration ?? 0) + duration
                        decodeTicks += duration
                    } else {
                        totalDuration = nil
                    }
                    position += size
                }
                if !isReadable { break }
                cursor = position
            }
            guard isReadable else { continue }
            result.append(CameraTrackFragment(trackId: trackId, baseMediaDecodeTime: baseMediaDecodeTime, samples: samples, durationTicks: totalDuration))
        }
        return result
    }

    // MARK: the time stamp

    /// The base media decode time of the first track fragment in a fragment, as a time since 1970 in milliseconds, or nil when it has none.
    public static func firstDecodeTime(in fragment: Data) -> UInt64? {
        parseFragment(fragment).first?.baseMediaDecodeTime
    }

    /// Rewrites the `tfdt` time of every track fragment to `baseMediaDecodeTime`, so a recorded clip can stand in for a camera
    /// that stamps its fragments with the wall clock. Returns nil when a `tfdt` is the short form and cannot hold the value.
    public static func settingDecodeTime(_ fragment: Data, to baseMediaDecodeTime: UInt64) -> Data? {
        var bytes = [UInt8](fragment)
        var replaced = false
        for moof in boxes(bytes, from: 0, to: bytes.count) where moof.type == "moof" {
            for traf in allBoxes(bytes, "traf", in: moof) {
                guard let tfdt = firstBox(bytes, "tfdt", in: traf), tfdt.payloadStart + 12 <= tfdt.end, bytes[tfdt.payloadStart] == 1 else { return nil }
                for index in 0..<8 {
                    bytes[tfdt.payloadStart + 4 + index] = UInt8((baseMediaDecodeTime >> UInt64(56 - 8 * index)) & 0xff)
                }
                replaced = true
            }
        }
        return replaced ? Data(bytes) : nil
    }
}

/// CameraNALUnits looks inside a sample when the fragment's flags do not say whether it is a key frame.
enum CameraNALUnits {
    /// Whether the sample holds an IDR picture (H.264 type 5) or an intra random access picture (H.265 types 16 to 21). The NAL unit lengths are
    /// four bytes, which is what cameras write; a sample that does not parse that way is taken for a delta frame.
    static func containsKeyFrame(_ sample: Data) -> Bool {
        let bytes = [UInt8](sample)
        var offset = 0
        while offset + 5 <= bytes.count {
            let length = Int(CameraMP4.readUInt32(bytes, offset))
            let header = bytes[offset + 4]
            if header & 0x1f == 5 { return true }
            if (header >> 1) & 0x3f >= 16, (header >> 1) & 0x3f <= 21 { return true }
            guard length > 0 else { return false }
            offset += 4 + length
        }
        return false
    }
}
