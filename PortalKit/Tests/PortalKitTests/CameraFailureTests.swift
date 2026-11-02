import Foundation
import Testing

@testable import PortalKit

@Suite struct CameraFailureTests {
    @Test func aRefusalIsToldApartFromAFailure() {
        #expect(CameraFailure.classify(PortalError.notPermitted) == .notAllowed)
        #expect(CameraFailure.classify(PortalError.refused("HTTP 401")) == .notAllowed)
        #expect(CameraFailure.classify(PortalError.refused("HTTP 403")) == .notAllowed)
        #expect(CameraFailure.classify(PortalError.refused("HTTP 502")) == .unavailable)
        #expect(CameraFailure.classify(PortalError.refused("HTTP 404")) == .unavailable)
        #expect(CameraFailure.classify(URLError(.timedOut)) == .unavailable)
        #expect(CameraFailure.classify(PortalError.unreadableAnswer) == .unavailable)
    }

    @Test func theStatusIsReadFromTheRefusal() {
        #expect(CameraFailure.status(of: PortalError.refused("HTTP 502")) == 502)
        #expect(CameraFailure.status(of: PortalError.refused("nope")) == nil)
        #expect(CameraFailure.status(of: URLError(.timedOut)) == nil)
    }

    @Test func aSnapshotThatIsRefusedTwiceIsNotAllowedAndOneThatComesIsNoFailure() async {
        let refused = ScriptedTransport { _ in (401, Data()) }
        let denied = Connection(account: makeAccount(refreshToken: ""), transport: refused)
        #expect(await denied.snapshotFailure(controllerId: "k1", cameraId: "c1") == .notAllowed)
        let broken = ScriptedTransport { _ in (502, Data()) }
        #expect(await Connection(account: makeAccount(), transport: broken).snapshotFailure(controllerId: "k1", cameraId: "c1") == .unavailable)
        let fine = ScriptedTransport { _ in (200, Data([1, 2, 3])) }
        #expect(await Connection(account: makeAccount(), transport: fine).snapshotFailure(controllerId: "k1", cameraId: "c1") == nil)
    }

    @Test func aFailedPlaybackDialIsToldApartByWhatAPlainGetAnswers() {
        #expect(CameraPlaybackFailure.classify(statusCode: 401) == .notAllowed)
        #expect(CameraPlaybackFailure.classify(statusCode: 403) == .notAllowed)
        // An older controller answers the route with its web page; a Portal without the route says not found.
        #expect(CameraPlaybackFailure.classify(statusCode: 200) == .unsupported)
        #expect(CameraPlaybackFailure.classify(statusCode: 404) == .unsupported)
        #expect(CameraPlaybackFailure.classify(statusCode: 502) == .unreachable)
        #expect(CameraPlaybackFailure.classify(statusCode: 504) == .unreachable)
        #expect(CameraPlaybackFailure.classify(statusCode: nil) == .unreachable)
        // The route exists and the dial failed anyway: the controller is not answering.
        #expect(CameraPlaybackFailure.classify(statusCode: 400) == .unreachable)
    }

    @Test func theFailureIsFoundWithOneGetToThePlaybackRoute() async {
        let page = ScriptedTransport { _ in (200, Data("<html></html>".utf8)) }
        #expect(await Connection(account: makeAccount(), transport: page).playbackFailure(controllerId: "controller01", cameraId: "nvrcamera01") == .unsupported)
        #expect(page.requests.count == 1)
        #expect(page.requests.first?.url?.path == "/api/v1/unifiprotect/controller01/playback/nvrcamera01")
        let refused = ScriptedTransport { _ in (401, Data()) }
        #expect(await Connection(account: makeAccount(refreshToken: ""), transport: refused).playbackFailure(controllerId: "controller01", cameraId: "nvrcamera01") == .notAllowed)
        let down = ScriptedTransport { _ in (502, Data()) }
        #expect(await Connection(account: makeAccount(), transport: down).playbackFailure(controllerId: "controller01", cameraId: "nvrcamera01") == .unreachable)
    }
}
