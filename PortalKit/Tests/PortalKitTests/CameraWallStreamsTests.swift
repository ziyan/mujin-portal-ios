import Testing

@testable import PortalKit

@Suite("CameraWallStreams")
struct CameraWallStreamsTests {
    @Test func streamsUpToTheLimitAndTheRestWait() {
        var streams = CameraWallStreams(limit: 2)
        for identifier in ["a", "b", "c", "d"] { streams.request(identifier) }
        #expect(streams.streamingIds == ["a", "b"])
        #expect(streams.waitingIds == ["c", "d"])
        #expect(streams.isStreaming("a"))
        #expect(!streams.isStreaming("c"))
        #expect(streams.isWaiting("c"))
    }

    @Test func askingAgainChangesNothing() {
        var streams = CameraWallStreams(limit: 1)
        streams.request("a")
        streams.request("a")
        streams.request("b")
        streams.request("b")
        #expect(streams.streamingIds == ["a"])
        #expect(streams.waitingIds == ["b"])
    }

    @Test func aReleasedStreamGoesToTheLongestWaitingTile() {
        var streams = CameraWallStreams(limit: 1)
        for identifier in ["a", "b", "c"] { streams.request(identifier) }
        streams.release("a")
        #expect(streams.streamingIds == ["b"])
        #expect(streams.waitingIds == ["c"])
    }

    @Test func aWaitingTileThatLeavesLosesItsPlace() {
        var streams = CameraWallStreams(limit: 1)
        for identifier in ["a", "b", "c"] { streams.request(identifier) }
        streams.release("b")
        streams.release("a")
        #expect(streams.streamingIds == ["c"])
        #expect(streams.waitingIds.isEmpty)
    }

    @Test func releasingAnUnknownTileIsHarmless() {
        var streams = CameraWallStreams(limit: 2)
        streams.request("a")
        streams.release("zzz")
        #expect(streams.streamingIds == ["a"])
    }

    @Test func aTileThatFailedForGoodGivesItsStreamToTheLongestWaitingTile() {
        var streams = CameraWallStreams(limit: 1)
        for identifier in ["a", "b", "c"] { streams.request(identifier) }
        streams.fail("a")
        #expect(streams.streamingIds == ["b"])
        #expect(streams.waitingIds == ["c"])
        #expect(streams.hasFailed("a"))
        #expect(!streams.isStreaming("a"))
        #expect(!streams.isWaiting("a"))
    }

    @Test func aFailedTileDoesNotAskAgainUntilItHasLeftTheScreen() {
        var streams = CameraWallStreams(limit: 2)
        streams.request("a")
        streams.fail("a")
        streams.request("a")
        #expect(streams.streamingIds.isEmpty)
        #expect(streams.hasFailed("a"))
        streams.release("a")
        #expect(!streams.hasFailed("a"))
        streams.request("a")
        #expect(streams.streamingIds == ["a"])
    }

    @Test func aTileWithoutAStreamCannotFail() {
        var streams = CameraWallStreams(limit: 1)
        streams.request("a")
        streams.request("b")
        streams.fail("b")
        streams.fail("zzz")
        #expect(streams.failedIds.isEmpty)
        #expect(streams.waitingIds == ["b"])
    }

    @Test func aTileThatRanOutOfRetriesIsTriedAgainWhenAnotherTileLeaves() {
        var streams = CameraWallStreams(limit: 2)
        for identifier in ["a", "b"] { streams.request(identifier) }
        streams.fail("a", isFinal: false)
        #expect(streams.hasFailed("a"))
        #expect(streams.streamingIds == ["b"])
        streams.release("b")
        #expect(streams.streamingIds == ["a"])
        #expect(!streams.hasFailed("a"))
    }

    @Test func aWaitingVisibleTileComesBeforeATileThatRanOutOfRetries() {
        var streams = CameraWallStreams(limit: 2)
        for identifier in ["a", "b", "c"] { streams.request(identifier) }
        streams.fail("a", isFinal: false)
        #expect(streams.streamingIds == ["b", "c"])
        streams.request("d")
        streams.release("b")
        #expect(streams.streamingIds == ["c", "d"])
        #expect(streams.exhaustedIds == ["a"])
        streams.release("c")
        #expect(streams.streamingIds == ["d", "a"])
    }

    @Test func twoTilesThatRanOutOfRetriesDoNotPassOneStreamBackAndForth() {
        var streams = CameraWallStreams(limit: 1)
        streams.request("a")
        streams.request("b")
        streams.fail("a", isFinal: false)
        #expect(streams.streamingIds == ["b"])
        streams.fail("b", isFinal: false)
        #expect(streams.streamingIds.isEmpty)
        #expect(streams.exhaustedIds == ["a", "b"])
    }

    @Test func aTileThatLeftTheScreenNeverGetsAStream() {
        var streams = CameraWallStreams(limit: 1)
        for identifier in ["a", "b", "c"] { streams.request(identifier) }
        streams.release("b")
        streams.release("a")
        #expect(streams.streamingIds == ["c"])
        #expect(streams.waitingIds.isEmpty)
        streams.release("c")
        #expect(streams.streamingIds.isEmpty)
    }

    @Test func retainingTheShownTilesLetsGoOfTheRest() {
        var streams = CameraWallStreams(limit: 2)
        for identifier in ["a", "b", "c", "d"] { streams.request(identifier) }
        streams.fail("a")
        streams.retain(["c", "d"])
        #expect(streams.streamingIds == ["c", "d"])
        #expect(streams.waitingIds.isEmpty)
        #expect(streams.failedIds.isEmpty)
        #expect(streams.exhaustedIds.isEmpty)
    }

    @Test func noStreamLeaksAcrossManyTilesComingAndGoing() {
        var streams = CameraWallStreams(limit: 4)
        var seed: UInt64 = 7
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        let identifiers = (0..<20).map { "camera\($0)" }
        for _ in 0..<2_000 {
            let identifier = identifiers[next(identifiers.count)]
            switch next(4) {
            case 0, 1: streams.request(identifier)
            case 2: streams.release(identifier)
            default: streams.fail(identifier, isFinal: next(2) == 0)
            }
            #expect(streams.streamingIds.count <= 4)
            let everyId = streams.streamingIds + streams.waitingIds + streams.failedIds + streams.exhaustedIds
            #expect(Set(everyId).count == everyId.count)
            // A tile waits only when every stream is taken.
            #expect(streams.waitingIds.isEmpty || streams.streamingIds.count == 4)
        }
        for identifier in identifiers { streams.release(identifier) }
        #expect(streams.streamingIds.isEmpty)
        #expect(streams.waitingIds.isEmpty)
        #expect(streams.failedIds.isEmpty)
        #expect(streams.exhaustedIds.isEmpty)
    }

    @Test func theLimitCoversAFullScreenAndHasACeiling() {
        #expect(CameraWallStreams.phoneLimit >= 12)
        #expect(CameraWallStreams.tabletLimit > CameraWallStreams.phoneLimit)
        #expect(CameraWallStreams(limit: 1_000).limit == CameraWallStreams.tabletLimit)
    }

    @Test func tilesPlayTheLeastSharpChannel() {
        let channels = [
            CameraChannel(id: 0, isEnabled: true, width: 2688, height: 1512),
            CameraChannel(id: 1, isEnabled: true, width: 1280, height: 720),
            CameraChannel(id: 2, isEnabled: true, width: 640, height: 360),
        ]
        #expect(CameraWallStreams.tileQuality.channelId(of: channels) == 2)
        #expect(CameraWallStreams.tileQuality.channelId(of: nil) == 0)
        #expect(CameraRoutes.livePath(controllerId: "controller1", cameraId: "nvrcamera01", channel: 2) == "/api/v1/unifiprotect/controller1/livestream/nvrcamera01?channel=2")
    }
}
