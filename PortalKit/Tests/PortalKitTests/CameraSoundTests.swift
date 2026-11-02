import Foundation
import Testing

@testable import PortalKit

/// The descriptors of an `esds` box for MPEG-4 audio: the ES descriptor, the decoder configuration descriptor, and the AudioSpecificConfig.
private func descriptors(objectTypeIndication: UInt8 = 0x40, audioSpecificConfig: [UInt8]) -> Data {
    let specific = Data([0x05, UInt8(audioSpecificConfig.count)]) + Data(audioSpecificConfig)
    let configuration = Data([objectTypeIndication, 0x15, 0, 0, 0]) + BoxBuilder.uint32(128_000) + BoxBuilder.uint32(128_000) + specific
    let decoderConfiguration = Data([0x04, UInt8(configuration.count)]) + configuration
    let body = Data([0, 2, 0]) + decoderConfiguration
    return Data([0x03, UInt8(body.count)]) + body
}

/// AAC low complexity, 48 kHz, stereo.
private let lowComplexityStereo48k: [UInt8] = [0x11, 0x90]

private func aacTrack(id: UInt32, timescale: UInt32, descriptors: Data, entryType: String = "mp4a") -> Data {
    let tkhd = BoxBuilder.fullBox("tkhd", flags: 3, BoxBuilder.uint32(0) + BoxBuilder.uint32(0) + BoxBuilder.uint32(id) + Data(count: 68))
    let mdhd = BoxBuilder.fullBox("mdhd", BoxBuilder.uint32(0) + BoxBuilder.uint32(0) + BoxBuilder.uint32(timescale) + BoxBuilder.uint32(0) + Data(count: 4))
    let hdlr = BoxBuilder.fullBox("hdlr", BoxBuilder.uint32(0) + Data("soun".utf8) + Data(count: 12) + Data([0]))
    // Six reserved bytes, the data reference index, eight bytes, two channels, 16 bits, four bytes, then 48000 as 16.16.
    let header = Data(count: 6) + BoxBuilder.uint16(1) + Data(count: 8) + BoxBuilder.uint16(2) + BoxBuilder.uint16(16) + Data(count: 4) + BoxBuilder.uint16(48_000) + BoxBuilder.uint16(0)
    let entry = BoxBuilder.box(entryType, header + BoxBuilder.fullBox("esds", descriptors))
    let stsd = BoxBuilder.fullBox("stsd", BoxBuilder.uint32(1) + entry)
    return BoxBuilder.box("trak", tkhd + BoxBuilder.box("mdia", mdhd + hdlr + BoxBuilder.box("minf", BoxBuilder.box("stbl", stsd))))
}

private func initSegment(audio: Data) -> Data {
    BoxBuilder.box("ftyp", Data(count: 8))
        + BoxBuilder.box(
            "moov",
            BoxBuilder.videoTrack(
                id: 1, timescale: 90_000, entryType: "avc1", configurationType: "avcC",
                configuration: BoxBuilder.avcConfiguration(sequenceSets: [sequenceSet], pictureSets: [pictureSet]), width: 1920, height: 1080) + audio)
}

private let videoConfiguration = CameraVideoConfiguration(
    trackId: 1, timescale: 90_000, codec: .h264, width: 1920, height: 1080, nalLengthSize: 4, parameterSets: [sequenceSet, pictureSet])
private let audioConfiguration = CameraAudioConfiguration(trackId: 2, timescale: 48_000, sampleRate: 48_000, channelCount: 2, magicCookie: Data())

/// A movie fragment of the shape the NVR sends: one `moof` with a track fragment for the video and one for the audio, and one `mdat`
/// holding the video samples and then the audio samples.
private struct TwoTrackFragment {
    var moof: Data
    var mdatHeader: Data
    var videoSamples: [Data]
    var audioSamples: [Data]

    var joined: Data { moof + mdatHeader + videoSamples.reduce(Data(), +) + audioSamples.reduce(Data(), +) }

    init(videoBase: UInt64, videoCount: Int, audioBase: UInt64, audioCount: Int) {
        let key = BoxBuilder.nalSample(types: [0x65])
        let delta = BoxBuilder.nalSample(types: [0x41])
        videoSamples = (0..<videoCount).map { $0 == 0 ? key : delta }
        audioSamples = (0..<audioCount).map { Data(repeating: UInt8(0x20 + $0), count: 9) }
        func trun(sizes: [Int], duration: UInt32, flags: [UInt32]?, dataOffset: UInt32) -> Data {
            let trunFlags: UInt32 = 0x001 | 0x100 | 0x200 | (flags == nil ? 0 : 0x400)
            var body = BoxBuilder.uint32(UInt32(sizes.count)) + BoxBuilder.uint32(dataOffset)
            for (index, size) in sizes.enumerated() {
                body += BoxBuilder.uint32(duration) + BoxBuilder.uint32(UInt32(size))
                if let flags { body += BoxBuilder.uint32(flags[index]) }
            }
            return BoxBuilder.fullBox("trun", version: 1, flags: trunFlags, body)
        }
        func traf(id: UInt32, base: UInt64, trun: Data) -> Data {
            BoxBuilder.box("traf", BoxBuilder.fullBox("tfhd", flags: 0x20000, BoxBuilder.uint32(id)) + BoxBuilder.fullBox("tfdt", version: 1, BoxBuilder.uint64(base)) + trun)
        }
        let videoFlags = (0..<videoCount).map { $0 == 0 ? UInt32(0x0200_0000) : 0x0101_0000 }
        let videoSizes = videoSamples.map(\.count)
        let audioSizes = audioSamples.map(\.count)
        func build(videoOffset: UInt32, audioOffset: UInt32) -> Data {
            BoxBuilder.box(
                "moof",
                BoxBuilder.fullBox("mfhd", BoxBuilder.uint32(1))
                    + traf(id: 1, base: videoBase, trun: trun(sizes: videoSizes, duration: 3600, flags: videoFlags, dataOffset: videoOffset))
                    + traf(id: 2, base: audioBase, trun: trun(sizes: audioSizes, duration: 1024, flags: nil, dataOffset: audioOffset)))
        }
        let moofSize = build(videoOffset: 0, audioOffset: 0).count
        let videoOffset = UInt32(moofSize + 8)
        moof = build(videoOffset: videoOffset, audioOffset: videoOffset + UInt32(videoSizes.reduce(0, +)))
        mdatHeader = BoxBuilder.uint32(UInt32(8 + videoSizes.reduce(0, +) + audioSizes.reduce(0, +))) + Data("mdat".utf8)
    }

    /// The frames of one segment as the playback socket sends them: every sample as its own frame with the video and audio interleaved, and
    /// the `moof` in pieces after them (its header, then each track fragment), then the `mdat` header and the end.
    var wireFrames: [CameraFrame] {
        var frames = [CameraFrame(typeByte: 249, payload: Data())]
        for index in 0..<max(videoSamples.count, audioSamples.count) {
            if index < videoSamples.count { frames.append(CameraFrame(typeByte: 252, payload: videoSamples[index])) }
            for audioIndex in [index * 2, index * 2 + 1] where audioIndex < audioSamples.count {
                frames.append(CameraFrame(typeByte: 253, payload: audioSamples[audioIndex]))
            }
        }
        var offset = 0
        let bytes = [UInt8](moof)
        let sizes = [24] + CameraMP4.boxes(bytes, from: 24, to: bytes.count).map { $0.end - $0.start }
        for size in sizes {
            frames.append(CameraFrame(typeByte: 251, payload: Data(bytes[offset..<(offset + size)])))
            offset += size
        }
        frames.append(CameraFrame(typeByte: 254, payload: mdatHeader))
        frames.append(CameraFrame(typeByte: 255, payload: Data()))
        return frames
    }
}

@Suite struct CameraSoundTests {
    @Test func theAACTrackIsReadFromTheInitializationSegment() throws {
        let cookie = descriptors(audioSpecificConfig: lowComplexityStereo48k)
        let segment = try CameraMP4.parseInitSegment(initSegment(audio: aacTrack(id: 2, timescale: 48_000, descriptors: cookie)))
        #expect(segment.hasAudio)
        let audio = try #require(segment.audio)
        #expect(audio.trackId == 2)
        #expect(audio.timescale == 48_000)
        #expect(audio.sampleRate == 48_000)
        #expect(audio.channelCount == 2)
        #expect(audio.magicCookie == cookie)
        #expect(segment.video?.trackId == 1)
    }

    @Test func theSampleRateAndChannelsComeFromTheAudioSpecificConfig() throws {
        // AAC low complexity, 44.1 kHz (index 4), mono: 00010 0100 0001 000.
        let cookie = descriptors(audioSpecificConfig: [0x12, 0x08])
        let audio = try #require(try CameraMP4.parseInitSegment(initSegment(audio: aacTrack(id: 2, timescale: 44_100, descriptors: cookie))).audio)
        #expect(audio.sampleRate == 44_100)
        #expect(audio.channelCount == 1)
    }

    @Test func audioThatIsNotAACIsReportedButNotPlayed() throws {
        let mp3 = descriptors(objectTypeIndication: 0x6b, audioSpecificConfig: lowComplexityStereo48k)
        let segment = try CameraMP4.parseInitSegment(initSegment(audio: aacTrack(id: 2, timescale: 48_000, descriptors: mp3)))
        #expect(segment.hasAudio)
        #expect(segment.audio == nil)
        let other = try CameraMP4.parseInitSegment(initSegment(audio: aacTrack(id: 2, timescale: 48_000, descriptors: mp3, entryType: "ac-3")))
        #expect(other.audio == nil)
    }

    @Test func aCameraWithoutAudioHasNone() throws {
        let segment = try CameraMP4.parseInitSegment(initSegment(audio: Data()))
        #expect(!segment.hasAudio)
        #expect(segment.audio == nil)
    }

    @Test func descriptorsThatAreCutShortGiveNothingAndDoNotCrash() {
        let whole = [UInt8](descriptors(audioSpecificConfig: lowComplexityStereo48k))
        for length in 0..<whole.count {
            _ = CameraMP4.audioSpecificConfiguration(Array(whole.prefix(length)))
        }
        #expect(CameraMP4.audioSpecificConfiguration(Array(whole.prefix(whole.count - 1))) == nil)
    }

    @Test func audioIsPlacedOnTheVideosAxisWhenTheStampsAreTheWallClock() {
        let requested = 1_700_000_000_000.0
        var stitcher = CameraStitcher(configuration: videoConfiguration, audio: audioConfiguration, expectedEpochMS: requested)
        let videoBase = UInt64((requested - 2_000) / 1000 * 90_000)
        let audioBase = UInt64((requested - 2_000) / 1000 * 48_000)
        let stitched = stitcher.stitchAll(TwoTrackFragment(videoBase: videoBase, videoCount: 4, audioBase: audioBase, audioCount: 6).joined)
        #expect(stitcher.mode == .absolute)
        #expect(stitched.video.count == 4)
        #expect(stitched.audio.count == 6)
        #expect(stitched.audio.map(\.presentationTicks) == (0..<6).map { Int64(audioBase) + Int64($0) * 1024 })
        #expect(stitched.audio.allSatisfy { $0.durationTicks == 1024 })
        // The same instant on both tracks' clocks.
        let videoSeconds = Double(stitched.video[0].presentationTicks) / 90_000
        let audioSeconds = Double(stitched.audio[0].presentationTicks) / 48_000
        #expect(abs(videoSeconds - audioSeconds) < 0.0001)
    }

    @Test func audioFollowsTheVideoWhenAStreamIsLaidEndToEnd() {
        let requested = 1_700_000_000_000.0
        var stitcher = CameraStitcher(configuration: videoConfiguration, audio: audioConfiguration, expectedEpochMS: requested)
        // A stream that counts from zero, like the live one.
        let first = stitcher.stitchAll(TwoTrackFragment(videoBase: 0, videoCount: 3, audioBase: 0, audioCount: 6).joined)
        let second = stitcher.stitchAll(TwoTrackFragment(videoBase: 10_800, videoCount: 3, audioBase: 6144, audioCount: 6).joined)
        #expect(stitcher.mode == .sequence)
        let videoAnchor = Int64(requested / 1000 * 90_000)
        let audioAnchor = Int64(requested / 1000 * 48_000)
        #expect(first.video[0].presentationTicks == videoAnchor)
        #expect(first.audio[0].presentationTicks == audioAnchor)
        #expect(second.video[0].presentationTicks == videoAnchor + 10_800)
        #expect(second.audio[0].presentationTicks == audioAnchor + 6144)
    }

    @Test func aWindowDoesNotPlayTheSoundOfTheStretchItRepeats() {
        let requested = 1_700_000_000_000.0
        var stitcher = CameraStitcher(configuration: videoConfiguration, audio: audioConfiguration, expectedEpochMS: requested)
        let videoBase = UInt64(requested / 1000 * 90_000)
        let audioBase = UInt64(requested / 1000 * 48_000)
        stitcher.beginWindow()
        let first = stitcher.stitchAll(TwoTrackFragment(videoBase: videoBase, videoCount: 10, audioBase: audioBase, audioCount: 20).joined)
        #expect(first.audio.count == 20)
        // The next window starts at the key frame four frames (3600 ticks of 90 kHz each) before the end of the last one.
        stitcher.beginWindow()
        let repeatedSeconds = 6 * 3600.0 / 90_000
        let secondAudioBase = audioBase + UInt64(repeatedSeconds * 48_000)
        let second = stitcher.stitchAll(TwoTrackFragment(videoBase: videoBase + 6 * 3600, videoCount: 8, audioBase: secondAudioBase, audioCount: 16).joined)
        #expect(second.video.map(\.isDisplayed) == [false, false, false, false, true, true, true, true])
        // The audio of the first 4 frames (0.16 s, which is 7.5 audio frames) is dropped: the 8 audio frames that end at or before it, and half of the next.
        #expect(second.audio.count < 16)
        #expect((second.audio.first?.presentationTicks ?? 0) >= Int64(secondAudioBase) + 6 * 1024)
    }

    @Test func aPlaybackSegmentOfInterleavedFramesWithTheMoofAtTheEndIsOneFragmentWithBothTracks() {
        let requested = 1_700_000_000_000.0
        let fragment = TwoTrackFragment(
            videoBase: UInt64(requested / 1000 * 90_000), videoCount: 12, audioBase: UInt64(requested / 1000 * 48_000), audioCount: 20)
        var decoder = CameraFrameDecoder()
        var assembler = CameraSegmentAssembler()
        var events: [CameraStreamEvent] = []
        // The socket cuts the bytes into messages anywhere, a frame often spanning two of them.
        let wire = CameraFrame(typeByte: 248, payload: Data("avc1.4d0029,mp4a.40.2".utf8)).encoded + fragment.wireFrames.reduce(Data()) { $0 + $1.encoded }
        var offset = 0
        while offset < wire.count {
            let end = min(offset + 37, wire.count)
            for frame in decoder.append(wire.subdata(in: offset..<end)) {
                if let event = assembler.accept(frame) { events.append(event) }
            }
            offset = end
        }
        #expect(events.count == 2)
        guard case .fragment(let data)? = events.last else {
            Issue.record("expected a fragment")
            return
        }
        #expect(data == fragment.joined)
        var stitcher = CameraStitcher(configuration: videoConfiguration, audio: audioConfiguration, expectedEpochMS: requested)
        let stitched = stitcher.stitchAll(data)
        #expect(stitched.video.count == 12)
        #expect(stitched.audio.count == 20)
        #expect(stitched.video.map(\.isSync) == [true] + Array(repeating: false, count: 11))
    }
}
