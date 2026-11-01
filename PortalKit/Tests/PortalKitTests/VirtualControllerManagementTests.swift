import Foundation
import Testing

@testable import PortalKit

@Suite struct VirtualControllerManagementTests {
    private func summary(status: String = "running", pausedAt: String? = nil, capabilities: [String]) -> VirtualControllerSummary {
        VirtualControllerSummary(id: "vc01", name: "Training cell", status: status, viewerCapabilities: capabilities, pausedAt: pausedAt)
    }

    @Test func buttonsFollowTheViewersCapabilities() {
        let manager = summary(capabilities: ["virtual_controller:modify", "virtual_controller:destroy"])
        #expect(manager.canModify && manager.canDestroy && manager.canTogglePause)
        let editor = summary(capabilities: ["virtual_controller:modify"])
        #expect(editor.canModify && !editor.canDestroy)
        let reader = summary(capabilities: [])
        #expect(!reader.canModify && !reader.canDestroy && !reader.canTogglePause)
    }

    @Test func nothingIsOfferedWhileItIsBeingDestroyedAndPauseNeedsARunningOrPausedOne() {
        #expect(!summary(status: "destroying", capabilities: ["virtual_controller:modify", "virtual_controller:destroy"]).canModify)
        #expect(!summary(status: "provisioning", capabilities: ["virtual_controller:modify"]).canTogglePause)
        #expect(summary(status: "paused", capabilities: ["virtual_controller:modify"]).canTogglePause)
        #expect(summary(status: "running", pausedAt: "2026-10-30T10:00:00Z", capabilities: []).isPaused)
    }

    @Test func pausingAndEditingSendTheRightRequests() async throws {
        let bodies = Guarded<[JSONValue]>([])
        let transport = ScriptedTransport { request in
            bodies.withValue { $0.append((try? JSONDecoder().decode(JSONValue.self, from: request.httpBody ?? Data())) ?? .null) }
            let query = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            if query.contains("ModifyVirtualController") {
                return (200, ScriptedTransport.json(["data": ["ModifyVirtualController": ["virtualController": ["id": "vc01", "name": "Renamed", "status": "running", "size": "medium"]]]]))
            }
            return (200, ScriptedTransport.json(["data": ["SetVirtualControllersPaused": ["virtualControllerIds": ["vc01"]]]]))
        }
        let account = Account(
            server: try ServerAddress("https://portal.example.test"), clientId: "client01", userId: "user01", displayName: "Alex", email: "alex@example.test",
            accessToken: "token", refreshToken: "refresh", accessTokenExpiresAt: Date().addingTimeInterval(3600))
        let connection = Connection(account: account, transport: transport)
        try await connection.setVirtualControllerPaused(id: "vc01", paused: true)
        let renamed = try await connection.modifyVirtualController(id: "vc01", name: "Renamed", size: "medium")
        #expect(renamed.name == "Renamed" && renamed.size == "medium")
        let sent = bodies.withValue { $0 }
        #expect(sent[0]["variables"]?["paused"] == .bool(true))
        #expect(sent[0]["variables"]?["virtualControllerIds"] == .array([.string("vc01")]))
        #expect(sent[1]["variables"]?["virtualController"]?["name"]?.stringValue == "Renamed")
        #expect(sent[1]["variables"]?["virtualController"]?["comment"] == nil)
    }
}
