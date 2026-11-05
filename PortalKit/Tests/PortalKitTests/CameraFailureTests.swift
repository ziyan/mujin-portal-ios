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
        // The route exists and the dial failed anyway: nothing says the controller is offline.
        #expect(CameraPlaybackFailure.classify(statusCode: 400) == .undetermined)
        #expect(CameraPlaybackFailure.classify(statusCode: 500) == .undetermined)
    }

    @Test func aSocketThatTheControllerClosedForWantOfFootageIsAGapNotAFault() {
        let noFootage = CameraSocketEnd.closed(code: 1011, reason: "no recorded footage for the requested window")
        #expect(CameraPlaybackFailure.classify(socketEnd: noFootage) == .noRecording)
        #expect(CameraPlaybackFailure.classify(socketEnd: .closed(code: 1011, reason: "No recorded footage in this window")) == .noRecording)
        // Other closes say too little, so the plain GET is asked.
        #expect(CameraPlaybackFailure.classify(socketEnd: .closed(code: 1011, reason: "upstream failed")) == nil)
        #expect(CameraPlaybackFailure.classify(socketEnd: .closed(code: 1000, reason: "no recorded footage")) == nil)
        #expect(CameraPlaybackFailure.classify(socketEnd: .broken) == nil)
        #expect(CameraPlaybackFailure.classify(socketEnd: nil) == nil)
    }

    @Test func aRefusedUpgradeIsToldApartByItsStatus() {
        #expect(CameraPlaybackFailure.classify(socketEnd: .refused(statusCode: 401)) == .notAllowed)
        #expect(CameraPlaybackFailure.classify(socketEnd: .refused(statusCode: 403)) == .notAllowed)
        #expect(CameraPlaybackFailure.classify(socketEnd: .refused(statusCode: 200)) == .unsupported)
        #expect(CameraPlaybackFailure.classify(socketEnd: .refused(statusCode: 404)) == .unsupported)
        #expect(CameraPlaybackFailure.classify(socketEnd: .refused(statusCode: 503)) == .unreachable)
        #expect(CameraPlaybackFailure.classify(socketEnd: .refused(statusCode: 400)) == nil)
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
        // A route that exists answers a plain GET with 400, which never says the controller is offline.
        let exists = ScriptedTransport { _ in (400, Data()) }
        #expect(await Connection(account: makeAccount(), transport: exists).playbackFailure(controllerId: "controller01", cameraId: "nvrcamera01") == .undetermined)
    }

    @Test func aRefusedOrMissingLiveRouteIsFinal() {
        #expect(CameraLiveFailure.classify(socketEnd: .refused(statusCode: 401)) == .notAllowed)
        #expect(CameraLiveFailure.classify(socketEnd: .refused(statusCode: 403)) == .notAllowed)
        #expect(CameraLiveFailure.classify(socketEnd: .refused(statusCode: 404)) == .routeMissing)
        #expect(CameraLiveFailure.notAllowed.isFinal)
        #expect(CameraLiveFailure.routeMissing.isFinal)
    }

    @Test func aDropOrATimeoutOfALiveStreamIsRetried() {
        #expect(CameraLiveFailure.classify(socketEnd: .broken) == .transient)
        #expect(CameraLiveFailure.classify(socketEnd: nil) == .transient)
        #expect(CameraLiveFailure.classify(socketEnd: .closed(code: 1011, reason: "upstream failed")) == .transient)
        #expect(CameraLiveFailure.classify(socketEnd: .closed(code: 1001, reason: "")) == .transient)
        for statusCode in [400, 408, 500, 502, 503, 504] {
            #expect(CameraLiveFailure.classify(socketEnd: .refused(statusCode: statusCode)) == .transient)
        }
        #expect(!CameraLiveFailure.transient.isFinal)
    }
}
