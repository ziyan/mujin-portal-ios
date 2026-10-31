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

    @Test func theAddressesTheAppBuildsAreTheOnesTheAppOpensAsControllers() throws {
        let server = try ServerAddress("https://portal.example.test")
        for url in [ControllerLinks.liveURL(controllerId: "controller01", server: server)!, ControllerLinks.cloudURL(controllerId: "controller01", server: server)!] {
            #expect(LinkClassifier.classify(url, server: server) == .controller)
        }
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

@Suite struct SiteOverviewTests {
    @Test func telemetryIsSummedOverTheMachinesThatAnswered() {
        let summaries = [
            TelemetrySummary(controllerId: "controller01", totals: .init(pickOperationCount: 120, pickedPartCount: 100, humanInterventionCount: 2, directRobotThroughputPartsPerHour: 40.25)),
            TelemetrySummary(controllerId: "controller02", totals: .init(pickOperationCount: 60, pickedPartCount: 50, humanInterventionCount: 1, directRobotThroughputPartsPerHour: 20)),
            TelemetrySummary(controllerId: "controller03", isAvailable: false, totals: .init(pickedPartCount: 999)),
        ]
        let telemetry = SiteTelemetry(summaries: summaries, machinesTotal: 3)
        #expect(telemetry.pickedParts == 150)
        #expect(telemetry.pickOperations == 180)
        #expect(telemetry.interventions == 3)
        #expect(telemetry.machinesReporting == 2 && telemetry.machinesTotal == 3)
        let english = Locale(identifier: "en_US")
        #expect(telemetry.errorRateText(locale: english) == "2%")
        #expect(telemetry.throughputText(locale: english) == "60.3")
        #expect(SiteTelemetry().errorRate == 0)
    }

    @Test func numbersAreGroupedAndThroughputKeepsADecimalOnlyBelowAHundred() {
        let english = Locale(identifier: "en_US")
        var telemetry = SiteTelemetry()
        telemetry.robotThroughputPartsPerHour = 1_395.8
        #expect(telemetry.throughputText(locale: english) == "1,396")
        telemetry.robotThroughputPartsPerHour = 58.25
        #expect(telemetry.throughputText(locale: english) == "58.3")
        telemetry.robotThroughputPartsPerHour = 12_345.4
        #expect(telemetry.throughputText(locale: english) == "12,345")
        #expect(telemetry.throughputText(locale: Locale(identifier: "de_DE")) == "12.345")
        #expect(telemetry.errorRateText(locale: english) == "0%")
    }

    @Test func aSectionShowsAtMostThreeRowsAndSaysWhenThereAreMore() {
        #expect(SiteSections.top([1, 2, 3, 4, 5]) == [1, 2, 3])
        #expect(SiteSections.hasMore([1, 2, 3, 4]))
        #expect(!SiteSections.hasMore([1, 2, 3]))
    }

    @Test func telemetryAsksForTheSitesMachinesOnly() async throws {
        let (connection, transport) = scriptedConnection { _, _ in
            ["ListControllerTelemetrySummaries": [["controllerId": "controller01", "isAvailable": true, "totals": ["pickedPartCount": 10, "pickOperationCount": 12, "humanInterventionCount": 1, "directRobotThroughputPartsPerHour": 5.0]]]]
        }
        let telemetry = try await connection.siteTelemetry(controllerIds: ["controller01"])
        #expect(telemetry.pickedParts == 10)
        #expect((sentVariables(try #require(transport.requests.last))["controllerIds"] as? [String]) == ["controller01"])
        #expect(try await connection.siteTelemetry(controllerIds: []) == SiteTelemetry())
    }

    @Test func aVirtualControllerKeepsItsNameAndOpensOnlyWhileItRuns() {
        let server = try! ServerAddress("https://portal.example.test")
        let running = VirtualControllerSummary(id: "virtual01", name: "Training cell", status: "running", viewerCapabilities: ["virtual_controller:connect"])
        #expect(running.displayName == "Training cell")
        #expect(VirtualControllerSummary(id: "virtual02").displayName == "virtual02")
        #expect(running.webEntry(server: server) == .open(URL(string: "https://virtual01-virtual.portal.example.test/")!))
        #expect(running.screenEntry(server: server) == .open(URL(string: "https://portal.example.test/screen/virtualcontroller/virtual01")!))
        let paused = VirtualControllerSummary(id: "virtual01", status: "paused", viewerCapabilities: ["virtual_controller:connect"])
        #expect(paused.webEntry(server: server) == .blocked(.notRunning))
        #expect(paused.screenEntry(server: server) == .blocked(.notRunning))
        #expect(VirtualControllerSummary(id: "virtual01", status: "running").webEntry(server: server) == .blocked(.noConnectPermission))
    }

    @Test func aCellKnowsItsMachines() async throws {
        let (connection, _) = scriptedConnection { _, _ in
            ["ListCells": ["cells": [["id": "cell01", "name": "Cell A", "controllerIds": ["controller01"], "virtualControllerIds": ["virtual01"]], ["id": "cell02", "isArchived": true]]]]
        }
        let cells = try await connection.cells(siteId: "site01")
        #expect(cells.map(\.id) == ["cell01"])
        #expect(cells.first?.machineCount == 2)
    }
}


@Suite struct SiteResourceTests {
    @Test func theOrchestratorRowCountsRunningOnesAndFlagsErrors() async throws {
        let (connection, _) = scriptedConnection { _, _ in
            [
                "ListSiteOrchestrators": [
                    [
                        "controllerId": "controller01", "isAvailable": true,
                        "orchestrators": ["activeRunModeName": "Normal", "orchestrators": [
                            ["orchestratorId": "o1", "orchestratorType": "picking", "runStatus": "running", "hasError": false],
                            ["orchestratorId": "o2", "orchestratorType": "packing", "runStatus": "stopped", "hasError": true, "statusMessage": "Gripper fault"],
                        ]],
                    ],
                    ["controllerId": "controller02", "isAvailable": false],
                ]
            ]
        }
        let rows = try await connection.siteOrchestrators(siteId: "site01")
        let summary = SiteOrchestratorSummary(rows)
        #expect(summary.runningCount == 1 && summary.totalCount == 2 && summary.hasError)
        #expect(summary.unreachableControllerCount == 1)
        #expect(rows[0].list[1].statusMessage == "Gripper fault")
    }

    @Test func membersAreNamedFromTheOrganizationsUsersAndSortedByName() async throws {
        let (connection, transport) = scriptedConnection { operation, _ in
            operation == "ListSiteUserIDs"
                ? ["ListSiteUserIDs": ["user02", "user01"]]
                : ["ListOrganizationUsers": ["users": [["id": "user01", "name": "Robin Demo", "email": "robin@example.test"], ["id": "user02", "name": "Alex Example", "email": "alex@example.test"], ["id": "user03", "name": "Not here"]]]]
        }
        let members = try await connection.siteMembers(siteId: "site01", organizationId: "organization01")
        #expect(members.map(\.shownName) == ["Alex Example", "Robin Demo"])
        #expect(sentVariables(try #require(transport.requests.last))["organizationId"] as? String == "organization01")
    }

    @Test func membersOfAnotherOrganizationAreNamedFromTheViewersOrganizationAndNoneIsDropped() async throws {
        let (connection, _) = scriptedConnection { operation, variables in
            if operation == "ListSiteUserIDs" { return ["ListSiteUserIDs": ["user01", "user02", "user03"]] }
            return variables["organizationId"] as? String == "organization01"
                ? ["ListOrganizationUsers": ["users": [["id": "user01", "name": "Robin Demo"]]]]
                : ["ListOrganizationUsers": ["users": [["id": "user02", "name": "Alex Example"]]]]
        }
        let members = try await connection.siteMembers(siteId: "site01", organizationId: "organization01", viewerOrganizationId: "organization09")
        #expect(members.map(\.id) == ["user02", "user01", "user03"])
        #expect(members.map(\.name) == ["Alex Example", "Robin Demo", nil])
    }

    @Test func membersAreShownToMujinUsersAndToAnAdministratorOfTheSitesOwnOrganization() {
        #expect(SiteMembersAccess.canSee(isMujinUser: true, permissions: [], viewerOrganizationId: "organization09", siteOrganizationId: "organization01"))
        #expect(SiteMembersAccess.canSee(isMujinUser: false, permissions: ["organization:operate-all"], viewerOrganizationId: "organization01", siteOrganizationId: "organization01"))
        #expect(!SiteMembersAccess.canSee(isMujinUser: false, permissions: ["organization:operate-all"], viewerOrganizationId: "organization02", siteOrganizationId: "organization01"))
        #expect(!SiteMembersAccess.canSee(isMujinUser: false, permissions: ["ticket:read"], viewerOrganizationId: "organization01", siteOrganizationId: "organization01"))
    }
}
