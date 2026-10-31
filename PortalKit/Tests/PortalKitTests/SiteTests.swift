import Foundation
import Testing

@testable import PortalKit

@Suite struct SiteTests {
    @Test func alarmsAreSortedWorstFirstThenNewest() async throws {
        let (connection, _) = scriptedConnection { _, _ in
            [
                "ListSiteActiveAlarms": [
                    ["controllerId": "c1", "isAvailable": true, "alarms": ["alarms": [
                        ["alarmLevel": "warning", "alarmMessage": "Low battery", "alarmStatus": "active", "occurredAt": "2026-03-01T10:00:00Z"],
                        ["alarmLevel": "error", "alarmMessage": "Gripper fault", "alarmStatus": "active", "occurredAt": "2026-03-01T09:00:00Z"],
                    ]]],
                    ["controllerId": "c2", "isAvailable": true, "alarms": ["alarms": [
                        ["alarmLevel": "error", "alarmMessage": "Camera lost", "alarmStatus": "active", "occurredAt": "2026-03-01T11:00:00Z"],
                    ]]],
                    ["controllerId": "c3", "isAvailable": false, "alarms": NSNull()],
                ]
            ]
        }
        let result = try await connection.siteAlarms(siteId: "site01")
        #expect(result.alarms.map(\.message) == ["Camera lost", "Gripper fault", "Low battery"])
        #expect(result.unavailableControllerCount == 1)
    }

    @Test func robotsAreCountedAndErrorsComeFirst() async throws {
        let (connection, _) = scriptedConnection { _, _ in
            [
                "ListSiteMobileRobots": [
                    ["controllerId": "c1", "isAvailable": true, "mobileRobots": ["robots": [
                        ["name": "robot_2", "isOnline": true, "hasError": false, "powerLevel": 0.8],
                        ["name": "robot_1", "isOnline": false, "hasError": true, "error": "Lost localization"],
                    ]]],
                    ["controllerId": "c2", "isAvailable": false, "mobileRobots": NSNull()],
                ]
            ]
        }
        let robots = try await connection.siteRobots(siteId: "site01")
        #expect(robots.robotCount == 2 && robots.onlineCount == 1 && robots.errorCount == 1)
        #expect(robots.robots.first?.name == "robot_1")
        #expect(robots.unavailableControllerCount == 1)
    }

    @Test func aControllerWithAConnectionIsOnline() {
        #expect(ControllerSummary(id: "c", connection: .init(id: "x")).isOnline)
        #expect(!ControllerSummary(id: "c").isOnline)
        #expect(!ControllerSummary(id: "c", connection: .init(id: "")).isOnline)
    }

    @Test func incidentsNeedingReviewComeFirstAndFilterBySite() {
        let all = [
            IncidentSummary(id: "i1", siteId: "site01", reviewStatus: "confirmed", detectedAt: "2026-03-03T10:00:00Z"),
            IncidentSummary(id: "i2", siteId: "site01", reviewStatus: "new", detectedAt: "2026-03-01T10:00:00Z"),
            IncidentSummary(id: "i3", siteId: "site02", reviewStatus: "new", detectedAt: "2026-03-02T10:00:00Z"),
        ]
        #expect(SiteData.incidents(all, siteId: "site01").map(\.id) == ["i2", "i1"])
        #expect(SiteData.incidents(all, siteId: nil).map(\.id) == ["i3", "i2", "i1"])
    }

    @Test func aControllerIsServedUnderTheServersHost() throws {
        let server = try ServerAddress("https://portal.example.test")
        #expect(ControllerSummary(id: "controller01").webURL(server: server)?.absoluteString == "https://controller01.portal.example.test/")
        #expect(LinkClassifier.classify(ControllerSummary(id: "controller01").webURL(server: server)!, server: server) == .controller)
    }

    @Test func sitesCanBeLimitedToAnOrganization() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["ListSites": ["sites": [["id": "site01", "name": "site01"]]]] }
        _ = try await connection.sites(organizationId: "organization02")
        #expect(sentVariables(transport.requests[0])["organizationId"] as? String == "organization02")
    }

    @Test func evidenceKnowsItsImages() {
        #expect(IncidentEvidence(attachmentId: "a", contentType: "image/jpeg").isImage)
        #expect(!IncidentEvidence(attachmentId: "a", contentType: "video/mp4").isImage)
    }

    @Test func reviewSendsTheNewStatus() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["TransitionIncident": ["incident": ["id": "i1", "reviewStatus": "dismissed"]]] }
        try await connection.setIncidentReview(id: "i1", reviewStatus: "dismissed")
        #expect(sentVariables(transport.requests[0])["reviewStatus"] as? String == "dismissed")
    }
}
