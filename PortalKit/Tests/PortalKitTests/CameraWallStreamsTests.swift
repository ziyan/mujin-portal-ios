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

    @Test func tilesPlayTheLeastSharpChannel() {
        let channels = [
            CameraChannel(id: 0, isEnabled: true, width: 2688, height: 1512),
            CameraChannel(id: 1, isEnabled: true, width: 1280, height: 720),
            CameraChannel(id: 2, isEnabled: true, width: 640, height: 360),
        ]
        #expect(CameraWallStreams.tileQuality.channelId(of: channels) == 2)
        #expect(CameraWallStreams.tileQuality.channelId(of: nil) == 0)
        #expect(CameraRoutes.livePath(controllerId: "controller01", cameraId: "nvrcamera01", channel: 2) == "/api/v1/unifiprotect/controller01/livestream/nvrcamera01?channel=2")
    }
}
