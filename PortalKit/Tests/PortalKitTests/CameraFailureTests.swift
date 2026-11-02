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
}
