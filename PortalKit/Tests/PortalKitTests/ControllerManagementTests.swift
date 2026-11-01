import Foundation
import Testing

@testable import PortalKit

@Suite struct ControllerManagementTests {
    private func account() throws -> Account {
        Account(
            server: try ServerAddress("https://portal.example.test"), clientId: "client01", userId: "user01", displayName: "Alex", email: "alex@example.test",
            accessToken: "token", refreshToken: "refresh", accessTokenExpiresAt: Date().addingTimeInterval(3600))
    }

    @Test func actionsFollowTheCapabilitiesAtTheControllersSite() {
        let editor = ControllerSummary(id: "c1", viewerCapabilities: ["controller:edit", "backup:delete"])
        #expect(editor.canEdit && editor.canDeleteBackups)
        let reader = ControllerSummary(id: "c2", viewerCapabilities: ["controller:connect"])
        #expect(!reader.canEdit && !reader.canDeleteBackups)
        #expect(ControllerMoveAccess.canOffer(permissions: ["organization:operate-all"]))
        #expect(!ControllerMoveAccess.canOffer(permissions: ["ticket:read"]))
    }

    @Test func backupsArePagedAndNewestFirstAndDeletingSendsBothIds() async throws {
        let bodies = Guarded<[JSONValue]>([])
        let transport = ScriptedTransport { request in
            let body = try JSONDecoder().decode(JSONValue.self, from: request.httpBody!)
            bodies.withValue { $0.append(body) }
            if body["query"]?.stringValue?.contains("DeleteBackup") == true {
                return (200, ScriptedTransport.json(["data": ["DeleteBackup": ["backupId": "b1"]]]))
            }
            let after = Int(body["variables"]?["options"]?["after"]?.numberValue ?? 0)
            let all = (0..<3).map { ["id": "b\($0)", "label": "Backup \($0)", "createdAt": "2026-10-0\($0 + 1)T08:00:00Z", "sizeBytes": 1_000] as [String: Any] }
            return (200, ScriptedTransport.json(["data": ["ListBackups": ["backups": Array(all[after..<min(after + 2, 3)]), "meta": ["totalCount": 3]]]]))
        }
        let connection = Connection(account: try account(), transport: transport)
        let backups = try await connection.backups(controllerId: "c1", pageSize: 2)
        #expect(backups.map(\.id) == ["b2", "b1", "b0"])
        try await connection.deleteBackup(controllerId: "c1", backupId: "b1")
        let last = bodies.withValue { $0.last }
        #expect(last?["variables"]?["controllerId"]?.stringValue == "c1")
        #expect(last?["variables"]?["backupId"]?.stringValue == "b1")
    }

    @Test func syncProgressHasAFractionWhenTheTotalIsKnown() {
        #expect(ControllerSyncProgress(resourceType: "tickets", pushedCount: 25, totalCount: 100).fraction == 0.25)
        #expect(ControllerSyncProgress(resourceType: "tickets", pushedCount: 5, totalCount: 0).fraction == nil)
        #expect(ControllerSyncProgress(resourceType: "tickets", pushedCount: 500, totalCount: 100).fraction == 1)
    }

    @Test func aSitesReportNarrowsToOneController() {
        let alarms = [
            SiteAlarm(controllerId: "c1", level: "warning", message: "Low air", status: "active", occurredAt: nil, originLabel: nil),
            SiteAlarm(controllerId: "c2", level: "critical", message: "Stopped", status: "active", occurredAt: nil, originLabel: nil),
            SiteAlarm(controllerId: "c1", level: "critical", message: "Jam", status: "active", occurredAt: nil, originLabel: nil),
        ]
        #expect(ControllerLive.alarms(alarms, controllerId: "c1").map(\.message) == ["Jam", "Low air"])
        let incidents = [IncidentSummary(id: "i1", controllerId: "c1"), IncidentSummary(id: "i2", controllerId: "c2")]
        #expect(ControllerLive.incidents(incidents, controllerId: "c1").map(\.id) == ["i1"])
    }
}

@Suite struct ControllerListTests {
    @Test func theListIsPagedPastTwoHundredAndFilteredByTextAndSite() async throws {
        let calls = Guarded<[Int]>([])
        let transport = ScriptedTransport { request in
            let body = try JSONDecoder().decode(JSONValue.self, from: request.httpBody!)
            let after = Int(body["variables"]?["options"]?["after"]?.numberValue ?? 0)
            calls.withValue { $0.append(after) }
            let total = 450
            let rows = (after..<min(after + 200, total)).map { ["id": "controller\($0)", "comment": "Line \($0)", "siteId": $0 % 2 == 0 ? "site01" : "site02"] as [String: Any] }
            return (200, ScriptedTransport.json(["data": ["ListControllers": ["controllers": rows, "meta": ["totalCount": total]]]]))
        }
        let account = Account(
            server: try ServerAddress("https://portal.example.test"), clientId: "client01", userId: "user01", displayName: "Alex", email: "alex@example.test",
            accessToken: "token", refreshToken: "refresh", accessTokenExpiresAt: Date().addingTimeInterval(3600))
        let all = try await Connection(account: account, transport: transport).controllers()
        #expect(all.count == 450)
        #expect(calls.withValue { $0 } == [0, 200, 400])
        let names = ["site01": "Riverside depot", "site02": "Hillcrest hub"]
        #expect(ControllerFilter(query: "hillcrest").apply(all, siteNames: names).count == 225)
        #expect(ControllerFilter(query: "Line 7", siteId: "site02").apply(all, siteNames: names).count == 1 + 5)
    }
}
