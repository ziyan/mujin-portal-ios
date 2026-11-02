import Foundation
import Testing

@testable import PortalKit

private func configuration(timescale: UInt32 = 90_000) -> CameraVideoConfiguration {
    CameraVideoConfiguration(trackId: 1, timescale: timescale, codec: .h264, width: 1920, height: 1080, nalLengthSize: 4, parameterSets: [sequenceSet, pictureSet])
}

private func fragment(baseTime: UInt64, count: Int = 3, duration: UInt32 = 3000, trackId: UInt32 = 1) -> Data {
    let key = BoxBuilder.nalSample(types: [0x65])
    let delta = BoxBuilder.nalSample(types: [0x41])
    let samples = (0..<count).map { index in
        BoxBuilder.Sample(payload: index == 0 ? key : delta, duration: duration, flags: index == 0 ? 0x0200_0000 : 0x0101_0000)
    }
    return BoxBuilder.fragment(trackId: trackId, baseTime: baseTime, samples: samples)
}

@Suite struct CameraStitcherTests {
    @Test func aWallClockStampIsUsedAsItIs() {
        let requested = 1_700_000_000_000.0
        var stitcher = CameraStitcher(configuration: configuration(), expectedEpochMS: requested)
        // The NVR starts at the key frame before the moment asked for.
        let base = UInt64((requested - 4_000) / 1000 * 90_000)
        let samples = stitcher.stitch(fragment(baseTime: base))
        #expect(stitcher.mode == .absolute)
        #expect(samples.count == 3)
        #expect(samples.map(\.presentationTicks) == [Int64(base), Int64(base) + 3000, Int64(base) + 6000])
        #expect(samples.allSatisfy { $0.isDisplayed })
        #expect(samples.map(\.isSync) == [true, false, false])
        #expect(samples.allSatisfy { $0.decodeTicks == nil })
        #expect(abs(stitcher.epochMS(forAxisSeconds: Double(base) / 90_000) - (requested - 4_000)) < 0.001)
        #expect(stitcher.axisSeconds(forEpochMS: requested) == requested / 1000)
    }

    @Test func aStampFarFromTheAskedMomentIsLaidEndToEndFromIt() {
        let requested = 1_700_000_000_000.0
        var stitcher = CameraStitcher(configuration: configuration(), expectedEpochMS: requested)
        // A stream that counts from zero.
        let first = stitcher.stitch(fragment(baseTime: 0))
        let second = stitcher.stitch(fragment(baseTime: 0))
        #expect(stitcher.mode == .sequence)
        let anchor = Int64(requested / 1000 * 90_000)
        #expect(first.map(\.presentationTicks) == [anchor, anchor + 3000, anchor + 6000])
        #expect(second.map(\.presentationTicks) == [anchor + 9000, anchor + 12_000, anchor + 15_000])
        #expect(abs(stitcher.epochMS(forAxisSeconds: Double(anchor + 9000) / 90_000) - (requested + 100)) < 0.01)
        #expect(abs(stitcher.axisSeconds(forEpochMS: requested + 100) - Double(anchor + 9000) / 90_000) < 0.0001)
    }

    @Test func aWindowThatRepeatsTheEndOfTheLastOneIsDecodedButNotShownTwice() {
        let requested = 1_700_000_000_000.0
        var stitcher = CameraStitcher(configuration: configuration(), expectedEpochMS: requested)
        let base = UInt64(requested / 1000 * 90_000)
        stitcher.beginWindow()
        let first = stitcher.stitch(fragment(baseTime: base, count: 5))
        // The next window starts at a key frame two frames before the end of the last one.
        stitcher.beginWindow()
        let overlap = stitcher.stitch(fragment(baseTime: base + 9000, count: 5))
        #expect(first.allSatisfy { $0.isDisplayed })
        #expect(overlap.map(\.isDisplayed) == [false, false, true, true, true])
        #expect(overlap[0].isSync)
    }

    @Test func aTrackThatIsNotTheVideoIsNotStitchedAsVideo() {
        var stitcher = CameraStitcher(configuration: configuration(), expectedEpochMS: 1_700_000_000_000)
        #expect(stitcher.stitch(fragment(baseTime: 153_000_000_000, trackId: 2)).isEmpty)
        #expect(stitcher.mode == .undecided)
    }

    @Test func reorderedFramesKeepTheirDecodeTimes() throws {
        var stitcher = CameraStitcher(configuration: configuration(timescale: 10_240), expectedEpochMS: 0)
        let samples = stitcher.stitch(CameraFixtures.h265)
        // The clip counts from zero and so does the request, which makes it absolute.
        #expect(stitcher.mode == .absolute)
        #expect(samples.count == 10)
        #expect(samples.allSatisfy { $0.decodeTicks != nil })
        #expect(samples.allSatisfy { $0.isDisplayed })
    }

    @Test func theLiveClockMovesOnlyWhenTheFramesLagOrRunAway() {
        #expect(CameraLiveSync.rebasedSeconds(leadSeconds: 0.5, firstFrameSeconds: 100) == nil)
        #expect(CameraLiveSync.rebasedSeconds(leadSeconds: 2.9, firstFrameSeconds: 100) == nil)
        #expect(CameraLiveSync.rebasedSeconds(leadSeconds: -0.2, firstFrameSeconds: 100) == 100 - CameraLiveSync.cushionSeconds)
        #expect(CameraLiveSync.rebasedSeconds(leadSeconds: 5, firstFrameSeconds: 100) == 100 - CameraLiveSync.cushionSeconds)
    }
}

@Suite struct CameraRoutesTests {
    @Test func theRoutesAreTheProxysAndEscapeTheirSegments() {
        #expect(CameraRoutes.livePath(controllerId: "controller01", cameraId: "nvr camera/1", channel: 2) == "/api/v1/unifiprotect/controller01/livestream/nvr%20camera%2F1?channel=2")
        #expect(
            CameraRoutes.playbackPath(controllerId: "controller01", cameraId: "nvrcamera01", channel: 0, startMS: 1000.4, endMS: 2000.6)
                == "/api/v1/unifiprotect/controller01/playback/nvrcamera01?channel=0&start=1000&end=2001")
        #expect(CameraRoutes.bootstrapPath(controllerId: "controller01") == "/api/v1/unifiprotect/controller01/bootstrap")
    }

    @Test func aLiveSnapshotHasNoMomentAndARecordedOneNamesTheChannel() {
        #expect(CameraRoutes.snapshotPath(controllerId: "controller01", cameraId: "nvrcamera01") == "/api/v1/unifiprotect/controller01/snapshot/nvrcamera01")
        #expect(CameraRoutes.snapshotPath(controllerId: "controller01", cameraId: "nvrcamera01", cacheBust: 7) == "/api/v1/unifiprotect/controller01/snapshot/nvrcamera01?t=7")
        #expect(
            CameraRoutes.snapshotPath(controllerId: "controller01", cameraId: "nvrcamera01", atMS: 1234.5, channel: 2, cacheBust: 9)
                == "/api/v1/unifiprotect/controller01/snapshot/nvrcamera01?ts=1235&channel=2&t=9")
    }

    @Test func anExportNamesTheCameraChannelAndWindow() {
        #expect(
            CameraRoutes.exportPath(controllerId: "controller01", cameraId: "nvrcamera01", channel: 1, startMS: 1000, endMS: 61_000, isDownload: true)
                == "/api/v1/unifiprotect/controller01/video/export?camera=nvrcamera01&channel=1&start=1000&end=61000&download=true")
    }

    @Test func aSocketDialsWssForHttps() throws {
        let server = try ServerAddress("https://portal.example.test")
        let url = CameraRoutes.socketURL(server: server, path: CameraRoutes.livePath(controllerId: "controller01", cameraId: "nvrcamera01", channel: 0))
        #expect(url.absoluteString == "wss://portal.example.test/api/v1/unifiprotect/controller01/livestream/nvrcamera01?channel=0")
    }

    @Test func aLongSelectionIsCutIntoClipsTheExportAllows() {
        let clips = CameraRoutes.exportClips(startMS: 0, endMS: 75 * 60_000)
        #expect(clips.count == 3)
        #expect(clips.map(\.startMS) == [0.0, 1_800_000.0, 3_600_000.0])
        #expect(clips.map(\.endMS) == [1_800_000.0, 3_600_000.0, 4_500_000.0])
        #expect(CameraRoutes.exportClips(startMS: 5, endMS: 5).isEmpty)
    }
}

@Suite struct CameraHealthTests {
    @Test func aStreamIsStalledAfterTenSilentSeconds() {
        let start = Date(timeIntervalSince1970: 1000)
        #expect(!CameraStreamHealth.isStalled(lastFrameAt: start, now: start.addingTimeInterval(9.9)))
        #expect(CameraStreamHealth.isStalled(lastFrameAt: start, now: start.addingTimeInterval(10)))
        #expect(!CameraStreamHealth.isStalled(lastFrameAt: nil, now: start.addingTimeInterval(500)))
    }

    @Test func theReconnectDelayDoublesUpToThirtySeconds() {
        let delays = (0...7).map { CameraStreamHealth.reconnectDelay(consecutiveFailures: $0) }
        #expect(delays == [1, 1, 2, 4, 8, 16, 30, 30])
    }

    @Test func automaticRetriesStopAfterSixFailures() {
        #expect(CameraStreamHealth.canReconnectAutomatically(consecutiveFailures: 6))
        #expect(!CameraStreamHealth.canReconnectAutomatically(consecutiveFailures: 7))
    }

    @Test func onlyAStalledOrFailedStreamNeedsARebuild() {
        #expect(CameraStreamStatus.stalled.needsReconnect)
        #expect(CameraStreamStatus.failed.needsReconnect)
        #expect(!CameraStreamStatus.reconnecting.needsReconnect)
        #expect(!CameraStreamStatus.playing.needsReconnect)
    }
}

@Suite struct CameraPlaybackWindowTests {
    @Test func theFirstWindowOpensAtOnceAndEndsAMinuteLater() {
        var windows = CameraPlaybackWindows(startMS: 1_000_000, endMS: 10_000_000)
        #expect(windows.plan(bufferedEndMS: 1_000_000, playheadMS: 1_000_000, speed: 1, isWindowOpen: false) == .open(startMS: 1_000_000, endMS: 1_060_000))
        #expect(windows.nextStartMS == 1_060_000)
    }

    @Test func nothingOpensWhileOneIsStillArriving() {
        var windows = CameraPlaybackWindows(startMS: 0, endMS: 10_000_000)
        #expect(windows.plan(bufferedEndMS: 0, playheadMS: 0, speed: 1, isWindowOpen: true) == .wait)
        #expect(windows.nextStartMS == 0)
    }

    @Test func theNextOpensWhenLessThanTwentySecondsAreLeftAhead() {
        var windows = CameraPlaybackWindows(startMS: 60_000, endMS: 10_000_000)
        #expect(windows.plan(bufferedEndMS: 60_000, playheadMS: 30_000, speed: 1, isWindowOpen: false) == .wait)
        #expect(windows.plan(bufferedEndMS: 60_000, playheadMS: 41_000, speed: 1, isWindowOpen: false) == .open(startMS: 60_000, endMS: 120_000))
    }

    @Test func fasterPlaybackKeepsMoreFootageAhead() {
        var windows = CameraPlaybackWindows(startMS: 60_000, endMS: 10_000_000)
        // 30 seconds ahead is plenty at 1x and not enough at 4x, which eats it four times as fast.
        #expect(windows.plan(bufferedEndMS: 60_000, playheadMS: 30_000, speed: 1, isWindowOpen: false) == .wait)
        #expect(windows.plan(bufferedEndMS: 60_000, playheadMS: 30_000, speed: 4, isWindowOpen: false) == .open(startMS: 60_000, endMS: 120_000))
    }

    @Test func theLastWindowStopsAtTheEndAndThenThePlanIsFinished() {
        var windows = CameraPlaybackWindows(startMS: 100_000, endMS: 130_000)
        #expect(windows.plan(bufferedEndMS: 0, playheadMS: 0, speed: 1, isWindowOpen: false) == .open(startMS: 100_000, endMS: 130_000))
        #expect(windows.plan(bufferedEndMS: 0, playheadMS: 0, speed: 1, isWindowOpen: false) == .finished)
    }

    @Test func emptyWindowsDoubleTheNextOneUntilFifteenMinutes() {
        var windows = CameraPlaybackWindows(startMS: 0, endMS: 100_000_000)
        var lengths: [Double] = []
        for _ in 0..<6 {
            guard case .open(let start, let end) = windows.plan(bufferedEndMS: 0, playheadMS: 0, speed: 1, isWindowOpen: false) else {
                Issue.record("expected a window")
                return
            }
            lengths.append(end - start)
            windows.windowEnded(didDeliverFootage: false)
        }
        #expect(lengths == [60_000, 120_000, 240_000, 480_000, 900_000, 900_000])
    }

    @Test func aWindowWithFramesStartsTheGrowthOver() {
        var windows = CameraPlaybackWindows(startMS: 0, endMS: 100_000_000)
        windows.windowEnded(didDeliverFootage: false)
        windows.windowEnded(didDeliverFootage: false)
        #expect(windows.nextWindowMS == 240_000)
        windows.windowEnded(didDeliverFootage: true)
        #expect(windows.nextWindowMS == 60_000)
    }

    @Test func eightEmptyWindowsInARowMeanThereIsNoRecording() {
        var windows = CameraPlaybackWindows(startMS: 0, endMS: 100_000_000)
        for _ in 0..<8 { windows.windowEnded(didDeliverFootage: false) }
        #expect(windows.plan(bufferedEndMS: 0, playheadMS: 0, speed: 1, isWindowOpen: false) == .noRecording)
    }

    @Test func aWindowThatWentQuietBeforeItsEndIsContinuedFromWhereItStopped() {
        var windows = CameraPlaybackWindows(startMS: 0, endMS: 10_000_000)
        #expect(windows.plan(bufferedEndMS: 0, playheadMS: 0, speed: 1, isWindowOpen: false) == .open(startMS: 0, endMS: 60_000))
        // The NVR paused for good after twenty seconds of the minute.
        windows.windowEnded(didDeliverFootage: true, bufferedEndMS: 20_000)
        #expect(windows.nextStartMS == 20_000)
        #expect(windows.plan(bufferedEndMS: 20_000, playheadMS: 5_000, speed: 1, isWindowOpen: false) == .open(startMS: 20_000, endMS: 80_000))
    }

    @Test func aWindowThatReachedItsEndIsFollowedByTheNextMinute() {
        var windows = CameraPlaybackWindows(startMS: 0, endMS: 10_000_000)
        _ = windows.plan(bufferedEndMS: 0, playheadMS: 0, speed: 1, isWindowOpen: false)
        // The last key frame group is cut at the end asked for, so the footage stops a frame short of it.
        windows.windowEnded(didDeliverFootage: true, bufferedEndMS: 59_960)
        #expect(windows.nextStartMS == 60_000)
    }

    @Test func theLastWindowIsNotAskedForAgainWhereverItStopped() {
        var windows = CameraPlaybackWindows(startMS: 100_000, endMS: 130_000)
        _ = windows.plan(bufferedEndMS: 0, playheadMS: 0, speed: 1, isWindowOpen: false)
        // The recording may simply end before now.
        windows.windowEnded(didDeliverFootage: true, bufferedEndMS: 110_000)
        #expect(windows.plan(bufferedEndMS: 110_000, playheadMS: 100_000, speed: 1, isWindowOpen: false) == .finished)
    }

    @Test func aWindowThatBroughtNothingNewDoesNotMoveTheNextOneBack() {
        var windows = CameraPlaybackWindows(startMS: 0, endMS: 10_000_000)
        _ = windows.plan(bufferedEndMS: 0, playheadMS: 0, speed: 1, isWindowOpen: false)
        windows.windowEnded(didDeliverFootage: false, bufferedEndMS: 20_000)
        #expect(windows.nextStartMS == 60_000)
        #expect(windows.consecutiveEmptyWindows == 1)
    }

    @Test func moreIsComingWhileAWindowIsOpenOrTheEndIsNotAskedForYet() {
        var windows = CameraPlaybackWindows(startMS: 0, endMS: 100_000)
        #expect(windows.hasMoreComing(isWindowOpen: true))
        #expect(windows.hasMoreComing(isWindowOpen: false))
        _ = windows.plan(bufferedEndMS: 0, playheadMS: 0, speed: 1, isWindowOpen: false)
        _ = windows.plan(bufferedEndMS: 0, playheadMS: 0, speed: 1, isWindowOpen: false)
        #expect(!windows.hasMoreComing(isWindowOpen: false))
    }

    @Test func aSlowControllerGetsTimeToFindTheFootage() {
        #expect(CameraPlaybackWindows.firstFrameTimeout >= 10)
        #expect(CameraPlaybackWindows.idleSeconds < CameraPlaybackWindows.firstFrameTimeout)
    }
}

@Suite struct CameraPlaybackBufferingTests {
    @Test func theClockWaitsWhenItHasCaughtUpWithFootageThatIsStillComing() {
        #expect(CameraPlaybackBuffering.step(isHolding: false, leadSeconds: 0.05, isMoreComing: true) == .hold)
        #expect(CameraPlaybackBuffering.step(isHolding: false, leadSeconds: -3, isMoreComing: true) == .hold)
    }

    @Test func theClockNeverWaitsForFootageThatIsNotComing() {
        #expect(CameraPlaybackBuffering.step(isHolding: false, leadSeconds: 0, isMoreComing: false) == .keep)
        #expect(CameraPlaybackBuffering.step(isHolding: true, leadSeconds: 0, isMoreComing: false) == .resume)
    }

    @Test func theClockGoesOnOnlyWhenASecondOfFootageIsAhead() {
        #expect(CameraPlaybackBuffering.step(isHolding: true, leadSeconds: 0.4, isMoreComing: true) == .keep)
        #expect(CameraPlaybackBuffering.step(isHolding: true, leadSeconds: 1, isMoreComing: true) == .resume)
        #expect(CameraPlaybackBuffering.step(isHolding: false, leadSeconds: 0.5, isMoreComing: true) == .keep)
    }
}
