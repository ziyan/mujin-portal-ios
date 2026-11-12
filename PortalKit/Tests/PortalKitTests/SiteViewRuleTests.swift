import Foundation
import Testing

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

@testable import PortalKit

@Suite struct SiteViewRuleTests {
    static func query(_ request: URLRequest) -> String {
        let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        return body["query"] as? String ?? ""
    }

    static func alarm(_ level: String, _ message: String = "A message") -> SiteAlarm {
        SiteAlarm(controllerId: "controllerA", level: level, message: message, status: "active", occurredAt: nil, originLabel: nil)
    }

    /// Telemetry answers for invented controllers: each has 100 picked parts, except the source, which holds the whole site's 1,000.
    static func summaries(for ids: [String], unavailable: Set<String> = []) -> [[String: Any]] {
        ids.map { id in
            if unavailable.contains(id) { return ["controllerId": id, "isAvailable": false] }
            let picked = id == "controllerSource" ? 1_000 : 100
            return ["controllerId": id, "isAvailable": true, "totals": ["pickedPartCount": picked, "pickOperationCount": picked, "humanInterventionCount": 0, "directRobotThroughputPartsPerHour": 0.0]]
        }
    }

    static func telemetryConnection(unavailable: Set<String> = []) -> (connection: Connection, transport: ScriptedTransport) {
        scriptedConnection { operation, variables in
            guard operation == "ListControllerTelemetrySummaries" else { return [:] }
            return ["ListControllerTelemetrySummaries": summaries(for: variables["controllerIds"] as? [String] ?? [], unavailable: unavailable)]
        }
    }

    static func requestedControllerIds(_ transport: ScriptedTransport) -> [[String]] {
        transport.requests.map { sentVariables($0)["controllerIds"] as? [String] ?? [] }
    }

    // MARK: - Capabilities

    @Test func theQueryThatNamesTheExcludedControllersIsHowTheServerIsRecognized() {
        #expect(!ServerCapabilities().offersSiteExclusion)
        #expect(!ServerCapabilities(queryNames: ["ListSites"]).offersSiteExclusion)
        #expect(ServerCapabilities(queryNames: ["ListSiteExcludedControllerIDs"]).offersSiteExclusion)
        #expect(ServerCapabilities(queryNames: ["listSiteExcludedControllerIDs"]).offersSiteExclusion)
    }

    @Test func theTelemetrySourceNeedsTheFieldAsWellAsTheQuery() {
        #expect(!ServerCapabilities(queryNames: ["ListSiteExcludedControllerIDs"]).offersTelemetrySource)
        #expect(!ServerCapabilities(siteFieldNames: ["telemetrySourceControllerId"]).offersTelemetrySource)
        #expect(ServerCapabilities(queryNames: ["ListSiteExcludedControllerIDs"], siteFieldNames: ["telemetrySourceControllerId"]).offersTelemetrySource)
    }

    @Test func theSiteFieldsAreReadFromTheSchemaOfTheServer() async {
        let (connection, _) = scriptedConnection { _, _ in
            [
                "__schema": [
                    "queryType": ["fields": [["name": "listSiteExcludedControllerIDs", "args": [["name": "siteId"], ["name": "cellId"]]]]],
                    "mutationType": ["fields": []], "subscriptionType": NSNull(),
                ],
                "siteType": ["fields": [["name": "id"], ["name": "telemetrySourceControllerId"]]],
            ]
        }
        let capabilities = await connection.capabilities()
        #expect(capabilities.offersSiteExclusion && capabilities.offersTelemetrySource)
        let (withoutField, _) = scriptedConnection { _, _ in
            [
                "__schema": ["queryType": ["fields": [["name": "listSiteExcludedControllerIDs", "args": []]]], "mutationType": ["fields": []], "subscriptionType": NSNull()],
                "siteType": ["fields": [["name": "id"]]],
            ]
        }
        let older = await withoutField.capabilities()
        #expect(older.offersSiteExclusion && !older.offersTelemetrySource)
    }

    @Test func anOlderServerIsNotAskedForTheNewFields() async throws {
        let (connection, transport) = scriptedConnection { _, _ in
            ["ListControllers": ["controllers": [], "meta": ["totalCount": 0]], "GetController": ["id": "controllerA"], "ListSites": ["sites": [], "meta": ["totalCount": 0]]]
        }
        _ = try await connection.controllers()
        _ = try await connection.controller(id: "controllerA")
        _ = try await connection.sites()
        for request in transport.requests {
            #expect(!Self.query(request).contains("isExcludedFromSiteViews") && !Self.query(request).contains("telemetrySourceControllerId"))
        }
        _ = try await connection.controllers(includesExclusionFlag: true)
        _ = try await connection.controller(id: "controllerA", includesExclusionFlag: true)
        _ = try await connection.sites(includesTelemetrySource: true)
        let asked = transport.requests.suffix(3).map(Self.query)
        #expect(asked[0].contains("isExcludedFromSiteViews") && asked[1].contains("isExcludedFromSiteViews"))
        #expect(asked[2].contains("telemetrySourceControllerId"))
    }

    // MARK: - The excluded controllers

    @Test func aCellAsksForWhatItLeavesOutAndASiteAsksForWhatItDoes() async throws {
        let (connection, transport) = scriptedConnection { _, variables in
            ["ListSiteExcludedControllerIDs": variables["cellId"] == nil ? ["controllerSimulated", "controllerSpare"] : ["controllerSimulated"]]
        }
        #expect(try await connection.siteExcludedControllerIds(siteId: "siteA") == ["controllerSimulated", "controllerSpare"])
        #expect(sentVariables(try #require(transport.requests.last))["cellId"] == nil)
        #expect(try await connection.siteExcludedControllerIds(siteId: "siteA", cellId: "cellA") == ["controllerSimulated"])
        #expect(sentVariables(try #require(transport.requests.last))["cellId"] as? String == "cellA")
        #expect(sentVariables(try #require(transport.requests.last))["siteId"] as? String == "siteA")
    }

    @Test func theExcludedControllersLeaveTheTotals() async throws {
        let (connection, transport) = Self.telemetryConnection()
        let telemetry = try await connection.siteTelemetry(
            controllerIds: ["controllerA", "controllerSimulated", "controllerB"], excludedControllerIds: ["controllerSimulated"], sourceControllerId: nil, isCell: false)
        #expect(telemetry.pickedParts == 200 && telemetry.machinesTotal == 2 && telemetry.machinesReporting == 2)
        #expect(Self.requestedControllerIds(transport) == [["controllerA", "controllerB"]])
    }

    @Test func theExcludedControllersLeaveACellsTotalsToo() async throws {
        let (connection, transport) = Self.telemetryConnection()
        let telemetry = try await connection.siteTelemetry(
            controllerIds: ["controllerA", "controllerSimulated"], excludedControllerIds: ["controllerSimulated"], sourceControllerId: nil, isCell: true)
        #expect(telemetry.pickedParts == 100)
        #expect(Self.requestedControllerIds(transport) == [["controllerA"]])
    }

    // MARK: - The telemetry source

    @Test func aSiteWithASourceReadsItAlone() async throws {
        let (connection, transport) = Self.telemetryConnection()
        let telemetry = try await connection.siteTelemetry(
            controllerIds: ["controllerA", "controllerSource", "controllerB"], excludedControllerIds: [], sourceControllerId: "controllerSource", isCell: false)
        #expect(telemetry.pickedParts == 1_000)
        #expect(Self.requestedControllerIds(transport) == [["controllerSource"]])
    }

    @Test func aSiteAddsTheOthersUpWhenItsSourceDoesNotAnswer() async throws {
        let (connection, transport) = Self.telemetryConnection(unavailable: ["controllerSource"])
        let telemetry = try await connection.siteTelemetry(
            controllerIds: ["controllerA", "controllerSource", "controllerB"], excludedControllerIds: [], sourceControllerId: "controllerSource", isCell: false)
        #expect(telemetry.pickedParts == 200)
        #expect(Self.requestedControllerIds(transport) == [["controllerSource"], ["controllerA", "controllerB"]])
    }

    @Test func aSourceThatIsExcludedOrNotAtTheSiteIsNotRead() async throws {
        let (connection, transport) = Self.telemetryConnection()
        let telemetry = try await connection.siteTelemetry(
            controllerIds: ["controllerA", "controllerSource"], excludedControllerIds: ["controllerSource"], sourceControllerId: "controllerSource", isCell: false)
        #expect(telemetry.pickedParts == 100)
        #expect(Self.requestedControllerIds(transport) == [["controllerA"]])
    }

    @Test func aCellLeavesTheSourceOutBesideOtherControllersAndKeepsItAlone() {
        #expect(TelemetryScope.cellControllerIds(["controllerA", "controllerSource"], excluded: [], sourceControllerId: "controllerSource") == ["controllerA"])
        #expect(TelemetryScope.cellControllerIds(["controllerSource"], excluded: [], sourceControllerId: "controllerSource") == ["controllerSource"])
        #expect(TelemetryScope.cellControllerIds(["controllerA", "controllerB"], excluded: [], sourceControllerId: "controllerSource") == ["controllerA", "controllerB"])
        #expect(TelemetryScope.cellControllerIds(["controllerA", "controllerSource"], excluded: [], sourceControllerId: nil) == ["controllerA", "controllerSource"])
    }

    @Test func inACellTheSourceIsKeptOnceTheOthersAreExcluded() {
        // Only the physical controllers that count decide, so the source is alone once the other one is left out.
        #expect(
            TelemetryScope.cellControllerIds(["controllerSimulated", "controllerSource"], excluded: ["controllerSimulated"], sourceControllerId: "controllerSource")
                == ["controllerSource"])
    }

    @Test func aCellWithTheSourceAndVirtualControllersKeepsTheSource() async throws {
        let (connection, transport) = Self.telemetryConnection()
        _ = try await connection.siteTelemetry(
            controllerIds: ["controllerSource"], virtualControllerIds: ["virtualA"], excludedControllerIds: [], sourceControllerId: "controllerSource", isCell: true)
        #expect(Self.requestedControllerIds(transport) == [["controllerSource"]])
        #expect(sentVariables(try #require(transport.requests.last))["virtualControllerIds"] as? [String] == ["virtualA"])
    }

    // MARK: - A controller's own reads

    @Test func aControllersPageReadsTheControllerAndNotTheSite() async throws {
        let (connection, transport) = scriptedConnection { operation, _ in
            switch operation {
            case "ListControllerAlarms":
                return ["ListControllerActiveAlarms": ["alarms": [
                    ["logEntryId": "entry1", "alarmLevel": "warning", "alarmMessage": "Slow", "alarmStatus": "active"],
                    ["logEntryId": "entry2", "alarmLevel": "Critical", "alarmMessage": "Down", "alarmStatus": "active"],
                ]]]
            case "ListControllerOrchestrators":
                return ["ListControllerOrchestrators": ["activeRunModeName": "Normal", "orchestrators": [["orchestratorId": "orchestratorA", "orchestratorType": "fleet", "hasError": false]]]]
            case "ListControllerMobileRobots":
                return ["ListControllerMobileRobots": ["robots": [["name": "robotB", "isOnline": true, "hasError": false], ["name": "robotA", "isOnline": true, "hasError": true, "error": "Stuck"]]]]
            default: return [:]
            }
        }
        let alarms = try await connection.controllerAlarms(controllerId: "controllerA")
        #expect(alarms.map(\.message) == ["Down", "Slow"] && alarms.allSatisfy { $0.controllerId == "controllerA" })
        let orchestrators = try #require(try await connection.controllerOrchestrators(controllerId: "controllerA"))
        #expect(orchestrators.controllerId == "controllerA" && orchestrators.list.map(\.id) == ["orchestratorA"])
        let robots = try await connection.controllerRobots(controllerId: "controllerA")
        #expect(robots.map(\.name) == ["robotA", "robotB"])
        for request in transport.requests {
            #expect(!Self.query(request).contains("ListSite"))
            #expect(sentVariables(request)["controllerId"] as? String == "controllerA")
            #expect(sentVariables(request)["siteId"] == nil)
        }
        #expect(transport.requests.map(Self.query).allSatisfy { $0.contains("ListController") })
    }

    @Test func excludingAControllerSendsTheFlagAlone() async throws {
        let (connection, transport) = scriptedConnection { _, _ in ["ModifyController": ["controller": ["id": "controllerA", "isExcludedFromSiteViews": true]]] }
        try await connection.setControllerExcluded(id: "controllerA", isExcluded: true)
        let variables = sentVariables(try #require(transport.requests.last))
        #expect(variables["controllerId"] as? String == "controllerA")
        #expect((variables["controller"] as? [String: Any])?["isExcludedFromSiteViews"] as? Bool == true)
        #expect((variables["controller"] as? [String: Any])?.count == 1)
    }

    @Test func aControllerAndASiteDecodeWithAndWithoutTheNewFields() throws {
        let controller = try JSONDecoder().decode(ControllerSummary.self, from: Data(#"{"id":"controllerA","isExcludedFromSiteViews":true}"#.utf8))
        #expect(controller.isExcludedFromSiteViews == true)
        #expect(try JSONDecoder().decode(ControllerSummary.self, from: Data(#"{"id":"controllerB"}"#.utf8)).isExcludedFromSiteViews == nil)
        let site = try JSONDecoder().decode(SiteSummary.self, from: Data(#"{"id":"siteA","name":"Site A","telemetrySourceControllerId":"controllerSource"}"#.utf8))
        #expect(site.telemetrySourceControllerId == "controllerSource")
        #expect(try JSONDecoder().decode(SiteSummary.self, from: Data(#"{"id":"siteB","name":"Site B"}"#.utf8)).telemetrySourceControllerId == nil)
    }

    // MARK: - Alarm levels

    @Test func theDefaultFilterShowsCriticalAndErrorOnly() {
        let filter = AlarmLevelFilter()
        let alarms = [Self.alarm("critical"), Self.alarm("error"), Self.alarm("warning"), Self.alarm("info")]
        #expect(filter.visible(alarms).map(\.level) == ["critical", "error"])
        #expect(filter.hiddenCount(alarms) == 2)
    }

    @Test func levelsAreComparedWithoutRegardToCase() {
        let filter = AlarmLevelFilter()
        #expect(filter.shows(Self.alarm("CRITICAL")) && filter.shows(Self.alarm("Error")) && filter.shows(Self.alarm(" error ")))
        #expect(!filter.shows(Self.alarm("WARNING")) && !filter.shows(Self.alarm("Info")))
        #expect(AlarmLevelFilter.counts([Self.alarm("Warning"), Self.alarm("warning"), Self.alarm("ERROR")]) == [.warning: 2, .error: 1])
    }

    @Test func anAlarmOfAnUnknownLevelAlwaysShows() {
        var filter = AlarmLevelFilter(selectedLevels: [])
        #expect(filter.shows(Self.alarm("severe")) && filter.shows(Self.alarm("")))
        #expect(!filter.shows(Self.alarm("critical")))
        filter.toggle(.critical)
        #expect(filter.shows(Self.alarm("critical")) && filter.shows(Self.alarm("severe")))
        #expect(AlarmLevelFilter.counts([Self.alarm("severe")]).isEmpty)
    }

    @Test func theChosenLevelsAreRememberedAsText() {
        #expect(AlarmLevelFilter(storedText: nil) == AlarmLevelFilter())
        var filter = AlarmLevelFilter()
        filter.toggle(.warning)
        filter.toggle(.critical)
        #expect(filter.storedText == "error,warning")
        #expect(AlarmLevelFilter(storedText: filter.storedText) == filter)
        #expect(AlarmLevelFilter(storedText: "").selectedLevels.isEmpty)
        #expect(AlarmLevelFilter(storedText: "error,unheardof").selectedLevels == [.error])
    }

    @Test func aSiteWithOnlyWarningsShowsNoneByDefaultAndSaysHowManyAreHidden() {
        let alarms = [Self.alarm("warning"), Self.alarm("warning"), Self.alarm("info")]
        let filter = AlarmLevelFilter()
        #expect(filter.visible(alarms).isEmpty && filter.hiddenCount(alarms) == 3)
    }
}
