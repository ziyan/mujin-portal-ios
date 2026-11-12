import Foundation
import Testing

@testable import PortalKit

private func channel(_ id: Int, _ width: Int, enabled: Bool = true) -> CameraChannel {
    CameraChannel(id: id, name: nil, isEnabled: enabled, width: width, height: width * 9 / 16, fps: 30)
}

@Suite struct CameraModelTests {
    @Test func qualityPicksTheSharpestAndTheLeastSharpEnabledChannel() {
        let channels = [channel(2, 640), channel(0, 2688), channel(1, 1280), channel(3, 1920, enabled: false)]
        #expect(CameraQuality.high.channelId(of: channels) == 0)
        #expect(CameraQuality.medium.channelId(of: channels) == 1)
        #expect(CameraQuality.low.channelId(of: channels) == 2)
    }

    @Test func recordedPlaybackAsksForAChannelTheNVRRecords() {
        // The NVR records the sharpest and the least sharp channel and none in between, so the middle quality plays the sharpest recording.
        let channels = [channel(2, 640), channel(0, 2688), channel(1, 1280)]
        #expect(CameraQuality.high.recordedChannelId(of: channels) == 0)
        #expect(CameraQuality.medium.recordedChannelId(of: channels) == 0)
        #expect(CameraQuality.low.recordedChannelId(of: channels) == 2)
        #expect(CameraQuality.medium.recordedChannelId(of: [channel(0, 1920), channel(2, 640)]) == 0)
        #expect(CameraQuality.medium.recordedChannelId(of: nil) == 0)
        // Live video keeps the middle channel.
        #expect(CameraQuality.medium.channelId(of: channels) == 1)
    }

    @Test func thePlaybackRequestNamesTheCameraTheRecordedChannelAndTheWindowInWholeMilliseconds() throws {
        let camera = Camera(
            id: "registry01", controllerId: "controller1", originCameraId: "nvrcamera01", status: "online", isControllerConnected: true,
            channels: [channel(0, 1920), channel(1, 1024), channel(2, 640)])
        let path = CameraRoutes.playbackPath(camera: camera, quality: .medium, startMS: 1_700_000_000_000.4, endMS: 1_700_000_060_000.6)
        #expect(path == "/api/v1/unifiprotect/controller1/playback/nvrcamera01?channel=0&start=1700000000000&end=1700000060001")
        #expect(CameraRoutes.playbackPath(camera: camera, quality: .low, startMS: 1000, endMS: 2000).contains("channel=2&"))
        // The NVR's id is sent, not the registry's.
        #expect(!path.contains("registry01"))
        let url = CameraRoutes.socketURL(server: try ServerAddress("https://portal.example.com"), path: path)
        #expect(url.scheme == "wss")
        #expect(url.host == "portal.example.com")
    }

    @Test func aCameraWithOneStreamOffersNoChoice() {
        #expect(CameraQuality.offered(by: [channel(0, 1920)]).isEmpty)
        #expect(CameraQuality.offered(by: [channel(0, 1920), channel(2, 640)]) == [.low, .high])
        #expect(CameraQuality.offered(by: [channel(0, 1920), channel(1, 1280), channel(2, 640)]) == [.low, .medium, .high])
    }

    @Test func aCameraWithNoChannelsIsStreamedOnChannelZero() {
        #expect(CameraQuality.low.channelId(of: nil) == 0)
        #expect(CameraQuality.high.channelId(of: []) == 0)
    }

    @Test func aCameraIsStreamableOnlyWhenBothHalvesHold() {
        let online = Camera(id: "a", controllerId: "c", originCameraId: "o", status: "online", isControllerConnected: true)
        let controllerDown = Camera(id: "b", controllerId: "c", originCameraId: "o", status: "online", isControllerConnected: false)
        let cameraDown = Camera(id: "c", controllerId: "c", originCameraId: "o", status: "offline", isControllerConnected: true)
        #expect(online.isStreamable)
        #expect(!controllerDown.isStreamable)
        #expect(!cameraDown.isStreamable)
    }

    @Test func camerasThatCanBeWatchedComeFirstThenByNameLikeANumberedList() {
        let rows = [
            Camera(id: "1", controllerId: "c", originCameraId: "o1", name: "Dock 10", status: "online", isControllerConnected: true),
            Camera(id: "2", controllerId: "c", originCameraId: "o2", name: "Aisle", status: "offline", isControllerConnected: true),
            Camera(id: "3", controllerId: "c", originCameraId: "o3", name: "Dock 2", status: "online", isControllerConnected: true),
        ]
        #expect(CameraOrdering.ordered(rows).map(\.id) == ["3", "1", "2"])
    }

    @Test func aNamelessCameraIsNamedByTheNVRsId() {
        #expect(Camera(id: "1", controllerId: "c", originCameraId: "nvr01", name: "  ").displayName == "nvr01")
    }

    @Test func theSiteListIsReadAndOneBadRowDoesNotSpoilIt() async throws {
        let (connection, transport) = scriptedConnection { operation, _ in
            guard operation == "ListCameras" else { return [:] }
            return [
                "ListCameras": [
                    "cameras": [
                        ["id": "cam1", "controllerId": "controller1", "originCameraId": "nvr1", "name": "Dock door", "status": "online", "isControllerConnected": true,
                         "timeZone": "America/Chicago", "channels": [["id": 0, "isEnabled": true, "width": 1920, "height": 1080], ["id": 2, "isEnabled": true, "width": 640, "height": 360]]],
                        ["id": "broken", "controllerId": NSNull(), "originCameraId": "nvr2"],
                        NSNull(),
                    ]
                ]
            ]
        }
        let cameras = try await connection.cameras(siteId: "site01")
        #expect(cameras.map(\.id) == ["cam1"])
        #expect(cameras[0].timeZone == "America/Chicago")
        #expect(cameras[0].channels?.count == 2)
        #expect(sentVariables(transport.requests[0])["siteId"] as? String == "site01")
    }

    @Test func anIncidentsAnglesAreOpenedInFullWithThePrimaryFirst() async throws {
        let (connection, _) = scriptedConnection { operation, variables in
            switch operation {
            case "ListIncidentCameras":
                return [
                    "ListIncidentCameras": [
                        "incidentCameras": [
                            ["id": "ic1", "cameraId": "cam2", "isPrimary": false, "clipStartedAt": "2026-03-01T10:00:00Z"],
                            ["id": "ic2", "cameraId": "cam1", "isPrimary": true, "clipStartedAt": "2026-03-01T10:00:05Z"],
                            ["id": "ic3", "cameraId": "gone", "isPrimary": false],
                        ]
                    ]
                ]
            case "GetCamera":
                let identifier = variables["cameraId"] as? String ?? ""
                if identifier == "gone" { return ["GetCamera": ["camera": NSNull()]] }
                return ["GetCamera": ["camera": ["id": identifier, "controllerId": "controller1", "originCameraId": "nvr-\(identifier)", "name": identifier]]]
            default:
                return [:]
            }
        }
        let targets = try await connection.incidentCameraTargets(incidentId: "incident01")
        #expect(targets.map(\.camera.id) == ["cam1", "cam2"])
        #expect(targets[0].clipStartedAt == PortalDate.parse("2026-03-01T10:00:05Z"))
    }

    @Test func theNVRsZoneComesFromItsBootstrap() async {
        let transport = ScriptedTransport { request in
            #expect(request.url?.path == "/api/v1/unifiprotect/controller1/bootstrap")
            return (200, ScriptedTransport.json(["nvr": ["timezone": "Europe/Berlin"], "cameras": []]))
        }
        let connection = Connection(account: makeAccount(), transport: transport)
        #expect(await connection.nvrTimeZone(controllerId: "controller1") == "Europe/Berlin")
    }

    @Test func aBootstrapWithoutAValidZoneGivesNil() async {
        let missing = Connection(account: makeAccount(), transport: ScriptedTransport { _ in (200, ScriptedTransport.json(["nvr": [:]])) })
        #expect(await missing.nvrTimeZone(controllerId: "controller1") == nil)
        let invalid = Connection(account: makeAccount(), transport: ScriptedTransport { _ in (200, ScriptedTransport.json(["nvr": ["timezone": "Nowhere/Land"]])) })
        #expect(await invalid.nvrTimeZone(controllerId: "controller1") == nil)
        let offline = Connection(account: makeAccount(), transport: ScriptedTransport { _ in (502, Data()) })
        #expect(await offline.nvrTimeZone(controllerId: "controller1") == nil)
    }
}
