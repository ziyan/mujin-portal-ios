import Foundation

// A controller can be left out of its site's and cells' merged views, a site can name one controller that stands for the whole site,
// and active alarms are listed by level. The rules that do not depend on a screen are here.

extension ServerCapabilities {
    /// Leaving a controller out of site and cell views. The query that names the controllers left out is how an app tells that the
    /// server has it, and it ships with the controller flag, the site's telemetry source and the alarm levels.
    public var offersSiteExclusion: Bool { offersQuery("ListSiteExcludedControllerIDs") }

    /// The controller that stands for a whole site. A server could offer the query without the field, so the field is checked too.
    public var offersTelemetrySource: Bool { offersSiteExclusion && siteFieldNames.contains("telemetrySourceControllerId") }
}

// MARK: - Alarm levels

/// AlarmLevel is a level an active alarm can have, as the lists filter by it.
public enum AlarmLevel: String, CaseIterable, Identifiable, Sendable {
    case critical
    case error
    case warning
    case info

    public var id: String { rawValue }

    /// The two levels a list and its count show until the person chooses others.
    public static let defaultSelection: Set<AlarmLevel> = [.critical, .error]

    /// The level a server's word names, compared without regard to case. A word that names none is not a level.
    public init?(serverWord: String) {
        switch serverWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "critical", "fatal": self = .critical
        case "error", "alarm": self = .error
        case "warning", "warn": self = .warning
        case "info", "information", "notice": self = .info
        default: return nil
        }
    }
}

extension SiteAlarm {
    /// The alarm's level, or nil for a level the app does not know.
    public var knownLevel: AlarmLevel? { AlarmLevel(serverWord: level) }
}

/// AlarmLevelFilter is which levels an active alarm list shows. An alarm of a level nobody knows always shows, so a new kind of alarm is
/// never hidden by a filter that was made before it existed.
public struct AlarmLevelFilter: Equatable, Sendable {
    public var selectedLevels: Set<AlarmLevel>

    public init(selectedLevels: Set<AlarmLevel> = AlarmLevel.defaultSelection) {
        self.selectedLevels = selectedLevels
    }

    /// The filter kept on the device. Nothing kept is the default; a kept empty text is a filter that shows no known level.
    public init(storedText: String?) {
        guard let storedText else {
            self.init()
            return
        }
        self.init(selectedLevels: Set(storedText.split(separator: ",").compactMap { AlarmLevel(rawValue: String($0)) }))
    }

    public var storedText: String { AlarmLevel.allCases.filter { selectedLevels.contains($0) }.map(\.rawValue).joined(separator: ",") }

    public func shows(_ alarm: SiteAlarm) -> Bool {
        guard let level = alarm.knownLevel else { return true }
        return selectedLevels.contains(level)
    }

    public func visible(_ alarms: [SiteAlarm]) -> [SiteAlarm] { alarms.filter(shows) }

    /// How many alarms the filter hides.
    public func hiddenCount(_ alarms: [SiteAlarm]) -> Int { alarms.count - visible(alarms).count }

    public mutating func toggle(_ level: AlarmLevel) {
        if selectedLevels.contains(level) { selectedLevels.remove(level) } else { selectedLevels.insert(level) }
    }

    /// How many alarms each level has, for the count beside its name.
    public static func counts(_ alarms: [SiteAlarm]) -> [AlarmLevel: Int] {
        var counts: [AlarmLevel: Int] = [:]
        for alarm in alarms {
            if let level = alarm.knownLevel { counts[level, default: 0] += 1 }
        }
        return counts
    }
}

// MARK: - What counts at a site and in a cell

/// TelemetryScope decides which controllers a set of tiles adds up.
public enum TelemetryScope {
    /// The controllers of a site that count: all but the ones left out of site views.
    public static func siteControllerIds(_ controllerIds: [String], excluded: Set<String>) -> [String] {
        controllerIds.filter { !excluded.contains($0) }
    }

    /// The controllers of a cell that count. The site's telemetry source holds the whole site's figures, so it is left out beside other
    /// controllers, and kept when it is the only physical controller that counts. Virtual controllers do not take part in that choice.
    public static func cellControllerIds(_ controllerIds: [String], excluded: Set<String>, sourceControllerId: String?) -> [String] {
        let counted = siteControllerIds(controllerIds, excluded: excluded)
        guard let sourceControllerId, !sourceControllerId.isEmpty, counted.contains(sourceControllerId), counted.count > 1 else { return counted }
        return counted.filter { $0 != sourceControllerId }
    }
}

// MARK: - Documents

extension Documents {
    /// The controllers a site's views leave out, or those one of its cells does when `cellId` is given.
    public static let listSiteExcludedControllerIds = """
        query ListSiteExcludedControllerIDs($siteId: String, $cellId: String) {
          ListSiteExcludedControllerIDs(siteId: $siteId, cellId: $cellId)
        }
        """

    public static let modifyControllerExclusion = """
        mutation ModifyControllerExclusion($controllerId: String, $controller: ControllerInput) {
          ModifyController(controllerId: $controllerId, controller: $controller) { controller { id isExcludedFromSiteViews } }
        }
        """

    /// A controller's own reads. They never go through the site's: the site's may leave the controller out, or hold only the site's
    /// telemetry source, so a page that filtered them would go empty.
    public static let listControllerAlarms = """
        query ListControllerAlarms($controllerId: String) {
          ListControllerActiveAlarms(controllerId: $controllerId) { alarms { logEntryId alarmLevel alarmMessage alarmStatus occurredAt originLabel } }
        }
        """

    public static let listControllerOrchestrators = """
        query ListControllerOrchestrators($controllerId: String) {
          ListControllerOrchestrators(controllerId: $controllerId) {
            observedAt activeRunModeName
            orchestrators { orchestratorId orchestratorType processStatus runStatus hasError isProcessingCommand statusMessage state }
          }
        }
        """

    public static let listControllerRobots = """
        query ListControllerMobileRobots($controllerId: String) {
          ListControllerMobileRobots(controllerId: $controllerId) {
            robots { name status isOnline hasError error powerLevel isCharging isLoaded }
          }
        }
        """

    /// A controller document with the flag that marks a controller left out of site views. Used only where the server offers it.
    public static func withExclusionFlag(_ document: String) -> String {
        document.replacingOccurrences(of: "hypervisorState { version publishedAt }", with: "hypervisorState { version publishedAt } isExcludedFromSiteViews")
    }

    /// The sites document with the site's telemetry source. Used only where the server's Site type has the field.
    public static func withTelemetrySource(_ document: String) -> String {
        document.replacingOccurrences(of: "viewerCapabilities }", with: "viewerCapabilities telemetrySourceControllerId }")
    }

    static var siteViewRuleDocuments: [String] {
        [
            listSiteExcludedControllerIds, modifyControllerExclusion, listControllerAlarms, listControllerOrchestrators, listControllerRobots,
            withExclusionFlag(listControllers), withExclusionFlag(getController), withTelemetrySource(listSites),
        ]
    }
}

// MARK: - Reads

extension Connection {
    /// The ids of the controllers left out of a site's views, or of one cell's when `cellId` is set.
    public func siteExcludedControllerIds(siteId: String, cellId: String? = nil) async throws -> [String] {
        struct Answer: Decodable, Sendable { let ListSiteExcludedControllerIDs: [String?]? }
        let rows = try await execute(Documents.listSiteExcludedControllerIds, variables: Self.siteScope(siteId: siteId, cellId: cellId), as: Answer.self)
            .ListSiteExcludedControllerIDs ?? []
        return rows.compactMap { $0 }.filter { !$0.isEmpty }
    }

    /// A site's or cell's tiles. Controllers left out of site views never count. A site with a telemetry source reads it alone and,
    /// when it does not answer, adds the others up; a cell leaves the source out beside other controllers (see `TelemetryScope`).
    public func siteTelemetry(
        controllerIds: [String], virtualControllerIds: [String] = [], excludedControllerIds: Set<String>, sourceControllerId: String?, isCell: Bool
    ) async throws -> SiteTelemetry {
        if isCell {
            let counted = TelemetryScope.cellControllerIds(controllerIds, excluded: excludedControllerIds, sourceControllerId: sourceControllerId)
            return try await siteTelemetry(controllerIds: counted, virtualControllerIds: virtualControllerIds)
        }
        let counted = TelemetryScope.siteControllerIds(controllerIds, excluded: excludedControllerIds)
        if let sourceControllerId, !sourceControllerId.isEmpty, counted.contains(sourceControllerId) {
            let rows = try await telemetrySummaries(controllerIds: [sourceControllerId], virtualControllerIds: [])
            if rows.contains(where: { $0.controllerId == sourceControllerId && $0.isAvailable == true }) {
                return SiteTelemetry(summaries: rows, machinesTotal: counted.count + virtualControllerIds.count)
            }
            return try await siteTelemetry(controllerIds: counted.filter { $0 != sourceControllerId }, virtualControllerIds: virtualControllerIds)
        }
        return try await siteTelemetry(controllerIds: counted, virtualControllerIds: virtualControllerIds)
    }

    /// The alarms active on one controller, worst first, read from the controller and not from its site.
    public func controllerAlarms(controllerId: String) async throws -> [SiteAlarm] {
        struct Answer: Decodable, Sendable {
            struct Holder: Decodable, Sendable {
                struct Alarm: Decodable, Sendable {
                    let logEntryId: String?
                    let alarmLevel: String?
                    let alarmMessage: String?
                    let alarmStatus: String?
                    let occurredAt: String?
                    let originLabel: String?
                }
                let alarms: [Alarm]?
            }
            let ListControllerActiveAlarms: Holder?
        }
        let rows = try await execute(Documents.listControllerAlarms, variables: ["controllerId": .string(controllerId)], as: Answer.self)
            .ListControllerActiveAlarms?.alarms ?? []
        return rows.map {
            SiteAlarm(
                controllerId: controllerId, level: $0.alarmLevel ?? "", message: $0.alarmMessage ?? "", status: $0.alarmStatus ?? "",
                occurredAt: $0.occurredAt, originLabel: $0.originLabel, logEntryId: $0.logEntryId)
        }.sorted { $0.severityRank < $1.severityRank }
    }

    /// One controller's orchestrators, in the shape the site's list gives, read from the controller.
    public func controllerOrchestrators(controllerId: String) async throws -> SiteOrchestrators? {
        struct Answer: Decodable, Sendable { let ListControllerOrchestrators: SiteOrchestrators.Snapshot? }
        guard let snapshot = try await execute(Documents.listControllerOrchestrators, variables: ["controllerId": .string(controllerId)], as: Answer.self)
            .ListControllerOrchestrators
        else { return nil }
        return SiteOrchestrators(controllerId: controllerId, isAvailable: true, orchestrators: snapshot)
    }

    /// One controller's mobile robots, read from the controller.
    public func controllerRobots(controllerId: String) async throws -> [SiteRobots.Robot] {
        struct Answer: Decodable, Sendable {
            struct Holder: Decodable, Sendable {
                struct Robot: Decodable, Sendable {
                    let name: String?
                    let status: String?
                    let isLoaded: Bool?
                    let isOnline: Bool?
                    let hasError: Bool?
                    let error: String?
                    let powerLevel: Double?
                    let isCharging: Bool?
                }
                let robots: [Robot]?
            }
            let ListControllerMobileRobots: Holder?
        }
        let rows = try await execute(Documents.listControllerRobots, variables: ["controllerId": .string(controllerId)], as: Answer.self)
            .ListControllerMobileRobots?.robots ?? []
        return rows.map {
            SiteRobots.Robot(
                controllerId: controllerId, name: $0.name ?? "", isOnline: $0.isOnline ?? false, hasError: $0.hasError ?? false, errorText: $0.error,
                powerLevel: $0.powerLevel, isCharging: $0.isCharging ?? false, statusText: $0.status, isLoaded: $0.isLoaded)
        }.sorted { ($0.hasError ? 0 : 1, $0.name) < ($1.hasError ? 0 : 1, $1.name) }
    }

    /// Leaves a controller out of its site's and cells' views, or puts it back.
    public func setControllerExcluded(id: String, isExcluded: Bool) async throws {
        _ = try await execute(
            Documents.modifyControllerExclusion,
            variables: ["controllerId": .string(id), "controller": .object(["isExcludedFromSiteViews": .bool(isExcluded)])], as: JSONValue.self)
    }
}
