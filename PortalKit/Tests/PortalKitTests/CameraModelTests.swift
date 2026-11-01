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
                        ["id": "cam1", "controllerId": "controller01", "originCameraId": "nvr1", "name": "Dock door", "status": "online", "isControllerConnected": true,
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
                return ["GetCamera": ["camera": ["id": identifier, "controllerId": "controller01", "originCameraId": "nvr-\(identifier)", "name": identifier]]]
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
            #expect(request.url?.path == "/api/v1/unifiprotect/controller01/bootstrap")
            return (200, ScriptedTransport.json(["nvr": ["timezone": "Europe/Berlin"], "cameras": []]))
        }
        let connection = Connection(account: makeAccount(), transport: transport)
        #expect(await connection.nvrTimeZone(controllerId: "controller01") == "Europe/Berlin")
    }

    @Test func aBootstrapWithoutAValidZoneGivesNil() async {
        let missing = Connection(account: makeAccount(), transport: ScriptedTransport { _ in (200, ScriptedTransport.json(["nvr": [:]])) })
        #expect(await missing.nvrTimeZone(controllerId: "controller01") == nil)
        let invalid = Connection(account: makeAccount(), transport: ScriptedTransport { _ in (200, ScriptedTransport.json(["nvr": ["timezone": "Nowhere/Land"]])) })
        #expect(await invalid.nvrTimeZone(controllerId: "controller01") == nil)
        let offline = Connection(account: makeAccount(), transport: ScriptedTransport { _ in (502, Data()) })
        #expect(await offline.nvrTimeZone(controllerId: "controller01") == nil)
    }
}
