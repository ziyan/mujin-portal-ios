import Foundation
import Testing

@testable import PortalKit

// MARK: - building boxes by hand

enum BoxBuilder {
    static func uint32(_ value: UInt32) -> Data { Data([UInt8(value >> 24), UInt8((value >> 16) & 0xff), UInt8((value >> 8) & 0xff), UInt8(value & 0xff)]) }
    static func uint64(_ value: UInt64) -> Data { uint32(UInt32(value >> 32)) + uint32(UInt32(value & 0xffff_ffff)) }
    static func uint16(_ value: Int) -> Data { Data([UInt8(value >> 8), UInt8(value & 0xff)]) }

    static func box(_ type: String, _ payload: Data = Data()) -> Data {
        uint32(UInt32(8 + payload.count)) + Data(type.utf8) + payload
    }

    static func fullBox(_ type: String, version: UInt8 = 0, flags: UInt32 = 0, _ payload: Data = Data()) -> Data {
        box(type, uint32((UInt32(version) << 24) | flags) + payload)
    }

    /// A track header and media header with the given ids, then a video sample entry holding `configuration`.
    static func videoTrack(id: UInt32, timescale: UInt32, entryType: String, configurationType: String, configuration: Data, width: Int, height: Int) -> Data {
        let tkhd = fullBox("tkhd", flags: 3, uint32(0) + uint32(0) + uint32(id) + Data(count: 68))
        let mdhd = fullBox("mdhd", uint32(0) + uint32(0) + uint32(timescale) + uint32(0) + Data(count: 4))
        let hdlr = fullBox("hdlr", uint32(0) + Data("vide".utf8) + Data(count: 12) + Data([0]))
        let entryHeader = Data(count: 6) + uint16(1) + Data(count: 16) + uint16(width) + uint16(height) + Data(count: 50)
        let entry = box(entryType, entryHeader + box(configurationType, configuration))
        let stsd = fullBox("stsd", uint32(1) + entry)
        let stbl = box("stbl", stsd)
        let minf = box("minf", stbl)
        let mdia = box("mdia", mdhd + hdlr + minf)
        return box("trak", tkhd + mdia)
    }

    static func audioTrack(id: UInt32, timescale: UInt32) -> Data {
        let tkhd = fullBox("tkhd", flags: 3, uint32(0) + uint32(0) + uint32(id) + Data(count: 68))
        let mdhd = fullBox("mdhd", uint32(0) + uint32(0) + uint32(timescale) + uint32(0) + Data(count: 4))
        let hdlr = fullBox("hdlr", uint32(0) + Data("soun".utf8) + Data(count: 12) + Data([0]))
        return box("trak", tkhd + box("mdia", mdhd + hdlr))
    }

    static func avcConfiguration(sequenceSets: [Data], pictureSets: [Data], lengthSizeMinusOne: UInt8 = 3) -> Data {
        var data = Data([1, 100, 0, 40, 0xfc | lengthSizeMinusOne, 0xe0 | UInt8(sequenceSets.count)])
        for set in sequenceSets { data += uint16(set.count) + set }
        data += Data([UInt8(pictureSets.count)])
        for set in pictureSets { data += uint16(set.count) + set }
        return data
    }

    static func hevcConfiguration(arrays: [(type: UInt8, units: [Data])], lengthSizeMinusOne: UInt8 = 3) -> Data {
        var data = Data(count: 21) + Data([0xfc | lengthSizeMinusOne, UInt8(arrays.count)])
        for array in arrays {
            data += Data([0x80 | array.type]) + uint16(array.units.count)
            for unit in array.units { data += uint16(unit.count) + unit }
        }
        return data
    }

    struct Sample {
        var payload: Data
        var duration: UInt32 = 3000
        var flags: UInt32?
        var compositionOffset: Int32?
    }

    /// A fragment with one track: a `moof` with `tfhd`, `tfdt` and `trun`, then the `mdat`.
    static func fragment(trackId: UInt32, baseTime: UInt64, samples: [Sample], tfdtVersion: UInt8 = 1, trackFlags: UInt32 = 0x20000) -> Data {
        var trunFlags: UInt32 = 0x001 | 0x100 | 0x200
        if samples.contains(where: { $0.flags != nil }) { trunFlags |= 0x400 }
        if samples.contains(where: { $0.compositionOffset != nil }) { trunFlags |= 0x800 }
        func trun(dataOffset: UInt32) -> Data {
            var body = uint32(UInt32(samples.count)) + uint32(dataOffset)
            for sample in samples {
                body += uint32(sample.duration) + uint32(UInt32(sample.payload.count))
                if trunFlags & 0x400 != 0 { body += uint32(sample.flags ?? 0) }
                if trunFlags & 0x800 != 0 { body += uint32(UInt32(bitPattern: sample.compositionOffset ?? 0)) }
            }
            return fullBox("trun", version: 1, flags: trunFlags, body)
        }
        let tfhd = fullBox("tfhd", flags: trackFlags, uint32(trackId))
        let tfdt = tfdtVersion == 1 ? fullBox("tfdt", version: 1, uint64(baseTime)) : fullBox("tfdt", version: 0, uint32(UInt32(baseTime)))
        let mfhd = fullBox("mfhd", uint32(1))
        // The data offset is from the start of the moof to the first byte after the mdat header.
        let moofSize = 8 + mfhd.count + 8 + tfhd.count + tfdt.count + trun(dataOffset: 0).count
        let offset = UInt32(moofSize + 8)
        let moof = box("moof", mfhd + box("traf", tfhd + tfdt + trun(dataOffset: offset)))
        let mdat = box("mdat", samples.reduce(Data()) { $0 + $1.payload })
        return moof + mdat
    }

    /// A sample of NAL units behind four byte lengths.
    static func nalSample(types: [UInt8], payloadSize: Int = 6) -> Data {
        var data = Data()
        for type in types {
            data += uint32(UInt32(payloadSize + 1)) + Data([type]) + Data(repeating: 0xaa, count: payloadSize)
        }
        return data
    }
}

let sequenceSet = Data([0x67, 0x64, 0x00, 0x28, 0xac])
let pictureSet = Data([0x68, 0xee, 0x3c, 0x80])

// MARK: - frames

@Suite struct CameraFramingTests {
    @Test func aFrameSplitAcrossMessagesIsJoined() {
        var decoder = CameraFrameDecoder()
        let bytes = CameraFrame(typeByte: CameraFrameType.moof.rawValue, payload: Data([1, 2, 3, 4, 5])).encoded
        #expect(decoder.append(bytes.prefix(3)).isEmpty)
        #expect(decoder.pendingByteCount == 3)
        let frames = decoder.append(bytes.dropFirst(3))
        #expect(frames.count == 1)
        #expect(frames[0].type == .moof)
        #expect(Array(frames[0].payload) == [1, 2, 3, 4, 5])
        #expect(decoder.pendingByteCount == 0)
    }

    @Test func severalFramesInOneMessageComeOutInOrder() {
        var decoder = CameraFrameDecoder()
        let message =
            CameraFrame(typeByte: 249, payload: Data()).encoded + CameraFrame(typeByte: 252, payload: Data([9, 9])).encoded
            + CameraFrame(typeByte: 255, payload: Data()).encoded
        let frames = decoder.append(message)
        #expect(frames.map(\.typeByte) == [249, 252, 255])
        #expect(Array(frames[1].payload) == [9, 9])
    }

    @Test func theLengthIsThreeBytesBigEndian() {
        var decoder = CameraFrameDecoder()
        let payload = Data(repeating: 7, count: 70_000)
        let frames = decoder.append(CameraFrame(typeByte: 252, payload: payload).encoded)
        #expect(frames.count == 1)
        #expect(frames[0].payload.count == 70_000)
    }

    @Test func manyFramesInARowDoNotLeaveTheBufferGrowing() {
        var decoder = CameraFrameDecoder()
        for index in 0..<200 {
            _ = decoder.append(CameraFrame(typeByte: 252, payload: Data(repeating: UInt8(index % 255), count: 100)).encoded)
        }
        #expect(decoder.pendingByteCount == 0)
    }

    @Test func aSegmentIsJoinedMoofThenMdatThenVideoThenAudio() {
        var assembler = CameraSegmentAssembler()
        var events: [CameraStreamEvent] = []
        let frames: [(UInt8, [UInt8])] = [(248, Array("avc1.640028".utf8)), (250, [1, 2]), (249, []), (254, [3]), (251, [4]), (252, [5]), (253, [6]), (255, [])]
        for (type, payload) in frames {
            if let event = assembler.accept(CameraFrame(typeByte: type, payload: Data(payload))) { events.append(event) }
        }
        #expect(events == [.codec("avc1.640028"), .initSegment(Data([1, 2])), .fragment(Data([4, 3, 5, 6]))])
    }

    @Test func aBeginFrameDropsWhatWasHalfCollected() {
        var assembler = CameraSegmentAssembler()
        _ = assembler.accept(CameraFrame(typeByte: 249, payload: Data()))
        _ = assembler.accept(CameraFrame(typeByte: 251, payload: Data([1])))
        _ = assembler.accept(CameraFrame(typeByte: 249, payload: Data()))
        _ = assembler.accept(CameraFrame(typeByte: 251, payload: Data([2])))
        let event = assembler.accept(CameraFrame(typeByte: 255, payload: Data()))
        #expect(event == .fragment(Data([2])))
    }

    @Test func anEmptySegmentAndAnUnknownFrameGiveNothing() {
        var assembler = CameraSegmentAssembler()
        #expect(assembler.accept(CameraFrame(typeByte: 249, payload: Data())) == nil)
        #expect(assembler.accept(CameraFrame(typeByte: 200, payload: Data([1]))) == nil)
        #expect(assembler.accept(CameraFrame(typeByte: 255, payload: Data())) == nil)
    }
}

// MARK: - boxes

@Suite struct CameraMP4Tests {
    @Test func theH264TrackIsReadFromAnInitializationSegment() throws {
        let init264 = BoxBuilder.box("ftyp", Data(count: 8))
            + BoxBuilder.box(
                "moov",
                BoxBuilder.videoTrack(
                    id: 1, timescale: 90_000, entryType: "avc1", configurationType: "avcC",
                    configuration: BoxBuilder.avcConfiguration(sequenceSets: [sequenceSet], pictureSets: [pictureSet]), width: 1920, height: 1080)
                    + BoxBuilder.audioTrack(id: 2, timescale: 48_000))
        let segment = try CameraMP4.parseInitSegment(init264)
        #expect(segment.timescales == [1: 90_000, 2: 48_000])
        #expect(segment.hasAudio)
        let video = try #require(segment.video)
        #expect(video.codec == .h264)
        #expect(video.trackId == 1)
        #expect(video.width == 1920 && video.height == 1080)
        #expect(video.nalLengthSize == 4)
        #expect(video.parameterSets == [sequenceSet, pictureSet])
    }

    @Test func theH265ParameterSetsComeOutVideoSequencePicture() throws {
        let video = Data([0x40, 1, 2]), sequence = Data([0x42, 3, 4]), picture = Data([0x44, 5, 6]), sei = Data([0x4e, 7])
        let configuration = BoxBuilder.hevcConfiguration(arrays: [(39, [sei]), (32, [video]), (33, [sequence]), (34, [picture])], lengthSizeMinusOne: 3)
        let data = BoxBuilder.box(
            "moov",
            BoxBuilder.videoTrack(id: 3, timescale: 90_000, entryType: "hvc1", configurationType: "hvcC", configuration: configuration, width: 2560, height: 1440))
        let track = try #require(try CameraMP4.parseInitSegment(data).video)
        #expect(track.codec == .h265)
        #expect(track.trackId == 3)
        #expect(track.nalLengthSize == 4)
        #expect(track.parameterSets == [video, sequence, picture])
    }

    @Test func aTwoByteNALLengthIsReported() throws {
        let configuration = BoxBuilder.avcConfiguration(sequenceSets: [sequenceSet], pictureSets: [pictureSet], lengthSizeMinusOne: 1)
        let data = BoxBuilder.box(
            "moov", BoxBuilder.videoTrack(id: 1, timescale: 1000, entryType: "avc3", configurationType: "avcC", configuration: configuration, width: 640, height: 360))
        #expect(try #require(try CameraMP4.parseInitSegment(data).video).nalLengthSize == 2)
    }

    @Test func aCodecThatIsNotH264OrH265IsNamed() {
        let data = BoxBuilder.box(
            "moov", BoxBuilder.videoTrack(id: 1, timescale: 1000, entryType: "vp09", configurationType: "vpcC", configuration: Data(count: 8), width: 640, height: 360))
        #expect(throws: CameraMP4Error.unsupportedCodec("vp09")) { try CameraMP4.parseInitSegment(data) }
    }

    @Test func noMoovAndATruncatedConfigurationAreErrors() {
        #expect(throws: CameraMP4Error.noMovieBox) { try CameraMP4.parseInitSegment(BoxBuilder.box("ftyp", Data(count: 8))) }
        let truncated = BoxBuilder.box(
            "moov",
            BoxBuilder.videoTrack(id: 1, timescale: 1000, entryType: "avc1", configurationType: "avcC", configuration: Data([1, 100, 0, 40, 0xff, 0xe1, 0, 20, 0x67]), width: 640, height: 360))
        #expect(throws: CameraMP4Error.malformedConfiguration) { try CameraMP4.parseInitSegment(truncated) }
    }

    @Test func aBoxThatOverrunsItsParentEndsTheWalk() {
        var bytes = [UInt8](BoxBuilder.box("free", Data(count: 4)))
        bytes += [0, 0, 0, 200] + Array("moov".utf8) + [0, 0]
        #expect(CameraMP4.boxes(bytes, from: 0, to: bytes.count).map(\.type) == ["free"])
    }

    @Test func aBoxThatSaysItIsEightBytesLongNeverLoopsForever() {
        let bytes: [UInt8] = [0, 0, 0, 4] + Array("junk".utf8) + [0, 0, 0, 0]
        #expect(CameraMP4.boxes(bytes, from: 0, to: bytes.count).isEmpty)
    }

    @Test func aFragmentGivesItsFramesWithTheirTiming() throws {
        let key = BoxBuilder.nalSample(types: [0x65])
        let delta = BoxBuilder.nalSample(types: [0x41])
        let data = BoxBuilder.fragment(
            trackId: 1, baseTime: 1_700_000_000 * 90_000,
            samples: [
                .init(payload: key, duration: 3000, flags: 0x0200_0000), .init(payload: delta, duration: 3000, flags: 0x0101_0000),
                .init(payload: delta, duration: 4500, flags: 0x0101_0000),
            ])
        let tracks = CameraMP4.parseFragment(data)
        let track = try #require(tracks.first)
        #expect(tracks.count == 1)
        #expect(track.trackId == 1)
        #expect(track.baseMediaDecodeTime == 1_700_000_000 * 90_000)
        #expect(track.durationTicks == 10_500)
        #expect(track.samples.map(\.isSync) == [true, false, false])
        #expect(track.samples.map(\.decodeTicks) == [153_000_000_000_000, 153_000_000_003_000, 153_000_000_006_000])
        #expect(track.samples[0].data == key)
        #expect(track.samples[2].data == delta)
    }

    @Test func compositionOffsetsMoveThePresentationTimeOnly() throws {
        let sample = BoxBuilder.nalSample(types: [0x41])
        let data = BoxBuilder.fragment(
            trackId: 1, baseTime: 9000,
            samples: [.init(payload: sample, flags: 0x0200_0000, compositionOffset: 6000), .init(payload: sample, flags: 0x0101_0000, compositionOffset: -3000)])
        let track = try #require(CameraMP4.parseFragment(data).first)
        #expect(track.samples.map(\.decodeTicks) == [9000, 12_000])
        #expect(track.samples.map(\.presentationTicks) == [15_000, 9000])
    }

    @Test func withoutFlagsTheNALUnitsSayWhichFrameIsAKeyFrame() throws {
        let data = BoxBuilder.fragment(
            trackId: 1, baseTime: 0,
            samples: [
                .init(payload: BoxBuilder.nalSample(types: [0x67, 0x68, 0x65])), .init(payload: BoxBuilder.nalSample(types: [0x41])),
                .init(payload: BoxBuilder.nalSample(types: [0x26])),
            ])
        let track = try #require(CameraMP4.parseFragment(data).first)
        #expect(track.samples.map(\.isSync) == [true, false, true])
    }

    @Test func aShortTimeStampIsRead() throws {
        let data = BoxBuilder.fragment(trackId: 1, baseTime: 4000, samples: [.init(payload: BoxBuilder.nalSample(types: [0x65]))], tfdtVersion: 0)
        #expect(try #require(CameraMP4.parseFragment(data).first).baseMediaDecodeTime == 4000)
    }

    @Test func aFragmentWhoseSamplesRunPastItsMediaDataGivesNothing() {
        var data = BoxBuilder.fragment(trackId: 1, baseTime: 0, samples: [.init(payload: BoxBuilder.nalSample(types: [0x65]))])
        data.removeLast(5)
        #expect(CameraMP4.parseFragment(data).isEmpty)
    }

    @Test func theTimeStampCanBeRewritten() throws {
        let data = BoxBuilder.fragment(trackId: 1, baseTime: 100, samples: [.init(payload: BoxBuilder.nalSample(types: [0x65]))])
        let moved = try #require(CameraMP4.settingDecodeTime(data, to: 153_000_000_000))
        #expect(CameraMP4.firstDecodeTime(in: moved) == 153_000_000_000)
        #expect(try #require(CameraMP4.parseFragment(moved).first).samples.count == 1)
        let short = BoxBuilder.fragment(trackId: 1, baseTime: 100, samples: [.init(payload: BoxBuilder.nalSample(types: [0x65]))], tfdtVersion: 0)
        #expect(CameraMP4.settingDecodeTime(short, to: 5) == nil)
    }

    // MARK: files made by an encoder

    @Test func anH264ClipFromAnEncoderIsRead() throws {
        let clip = CameraFixtures.h264
        let segment = try CameraMP4.parseInitSegment(clip)
        let video = try #require(segment.video)
        #expect(video.codec == .h264)
        #expect(video.width == 160 && video.height == 96)
        #expect(video.timescale == 10_240)
        #expect(video.parameterSets.count == 2)
        #expect(video.parameterSets[0].first.map { $0 & 0x1f } == 7)
        #expect(video.parameterSets[1].first.map { $0 & 0x1f } == 8)
        let fragments = CameraMP4.parseFragment(clip)
        #expect(fragments.count == 2)
        #expect(fragments.map(\.baseMediaDecodeTime) == [0, 10_240])
        #expect(fragments.map(\.samples.count) == [5, 5])
        #expect(fragments[0].samples.map(\.isSync) == [true, false, false, false, false])
        #expect(fragments[0].samples.allSatisfy { $0.durationTicks == 2048 })
        #expect(fragments[1].durationTicks == 10_240)
        // Every sample is whole NAL units behind four byte lengths.
        for sample in fragments.flatMap(\.samples) {
            var offset = 0
            let bytes = [UInt8](sample.data)
            while offset < bytes.count {
                let length = Int(CameraMP4.readUInt32(bytes, offset))
                offset += 4 + length
            }
            #expect(offset == bytes.count)
        }
    }

    @Test func anH265ClipWithReorderedFramesIsRead() throws {
        let clip = CameraFixtures.h265
        let video = try #require(try CameraMP4.parseInitSegment(clip).video)
        #expect(video.codec == .h265)
        #expect(video.width == 160 && video.height == 96)
        #expect(video.nalLengthSize == 4)
        #expect(video.parameterSets.count == 3)
        #expect(video.parameterSets.map { ($0[0] >> 1) & 0x3f } == [32, 33, 34])
        let fragments = CameraMP4.parseFragment(clip)
        #expect(fragments.count == 2)
        #expect(fragments.map(\.samples.count) == [5, 5])
        #expect(fragments[0].samples[0].isSync)
        let reordered = fragments[1].samples
        #expect(reordered.map(\.compositionOffsetTicks) == [4096, 6144, 2048, 6144, 2048])
        #expect(reordered.map(\.decodeTicks) == [10_240, 12_288, 14_336, 16_384, 18_432])
        #expect(reordered.map(\.presentationTicks) == [14_336, 18_432, 16_384, 22_528, 20_480])
    }
}
